import { createAlertMachine, STATES } from './core/alertStateMachine.js';
import { createFallDetector } from './core/fallDetector.js';
import { matchIntent, isEcho, INTENTS } from './core/voiceIntents.js';
import { encodeAlert, smsBody, mapLink } from './core/alertLink.js';
import {
  LANGS, LANG_SHORT, LANG_LABELS, EMERGENCY_HEADER, FIRST_AID_STEPS, COUNTDOWN_PROMPT, ANSWERS, ELAPSED_SPOKEN, EMERGENCY_NUMBER,
} from './core/content.js';
import { createVoiceService } from './services/voiceService.js';
import { say, stopSpeaking } from './services/speech.js';
import * as store from './services/storage.js';
import { sirenBurst, stopSiren, sirenPlaying } from './services/siren.js';
import { startLocation, lastLocation } from './services/location.js';
import { startMotion, stopMotion, simulateFall } from './services/motion.js';

const APP_NAME = 'P.A.Z.I.Y.O.N';
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const icon = (id, cls = 'icon') => `<svg class="${cls}" aria-hidden="true"><use href="#i-${id}"/></svg>`;

const data = store.load();
const persist = () => store.save(data);

const DEMO_PROFILES = {
  en: { name: 'Abebe Kebede', condition: 'Epilepsy', seizureType: 'Tonic-clonic', medications: 'Carbamazepine 200 mg', allergies: 'Penicillin', bloodType: 'O+' },
  am: { name: 'አበበ ከበደ', condition: 'Epilepsy', seizureType: 'Tonic-clonic', medications: 'Carbamazepine 200 mg', allergies: 'Penicillin', bloodType: 'O+' },
  om: { name: 'Caalaa Guddataa', condition: 'Epilepsy', seizureType: 'Tonic-clonic', medications: 'Carbamazepine 200 mg', allergies: 'Penicillin', bloodType: 'O+' },
};
const SOURCES = { voice: ['mic', 'Voice trigger'], manual: ['hand', 'Button pressed'], fall: ['sensors', 'Fall detected'] };

// ---------------------------------------------------------------- state machine

const machine = createAlertMachine({ cancelWindowSeconds: data.settings.cancelWindowSeconds });
setInterval(() => machine.tick(), 250);

let currentEvent = null;
let alertInfo = null;

machine.subscribe((snap) => {
  switch (snap.event) {
    case 'triggered': return onTriggered(snap);
    case 'countdown': return onCountdown(snap);
    case 'activated': return onActivated(snap);
    case 'tick': return renderElapsed(snap.elapsed);
    case 'cancelled':
    case 'resolved': return onFinished(snap);
    case 'reset': return onReset();
  }
});

// ---------------------------------------------------------------- spoken output

// What the phone said, so the microphone can ignore its own voice. Only
// speech that is still playing or ended in the last few seconds counts;
// otherwise a first-aid step like "Please help them" would block a real
// "help" long after the alert.
const ECHO_WINDOW_MS = 4000;
const spoken = [];
async function speak(text, lang, clipName) {
  const entry = { text, until: Infinity };
  spoken.push(entry);
  if (spoken.length > 8) spoken.shift();
  try {
    // Voxide's natural voice when connected; recorded clips / browser TTS otherwise.
    const spokenByAgent = agentLive() && (await agentSay(text, lang));
    if (!spokenByAgent) await say(text, lang, clipName);
  } finally {
    entry.until = Date.now() + ECHO_WINDOW_MS;
  }
}
const recentlySpoken = () => spoken.filter((e) => e.until > Date.now()).map((e) => e.text);

// ---------------------------------------------------------------- voice input

const voiceState = { status: 'off', detail: null, hearing: null };
// Voxide agent state (see the Voxide section below).
const agent = { engine: null, status: 'off', error: null, stopped: false, reading: 0 };
const agentWaiters = new Set();
let agentUtterance = 0;
let agentInUtterance = false;
let actedOnUtterance = null;

const voice = createVoiceService({
  // Act on the first interim result that matches, once per utterance: "help"
  // works the moment it is said and a question is never answered twice.
  onHeard({ text, isFinal, utterance }) {
    if (utterance === actedOnUtterance || isEcho(text, recentlySpoken())) return;
    voiceState.hearing = text.trim();
    renderVoice();
    if (route(text, isFinal)) actedOnUtterance = utterance;
  },
  onStatus(status, detail) {
    voiceState.status = status;
    voiceState.detail = detail;
    renderVoice();
  },
});

/** Returns whether the text was acted on. */
function route(text, isFinal) {
  const match = matchIntent(text, machine.state);
  switch (machine.state) {
    case STATES.IDLE:
      if (match?.intent === INTENTS.TRIGGER && data.settings.voiceTrigger) {
        machine.trigger('voice');
        return true;
      }
      return false;
    case STATES.COUNTDOWN:
      if (match?.intent === INTENTS.CANCEL) {
        machine.cancel('voice');
        return true;
      }
      return false;
    case STATES.ACTIVE:
      if (!match && !isFinal) return false; // wait for the question to finish
      addConvo('q', text);
      answerBystander(match);
      return true;
    default:
      return false;
  }
}

function typed(text) {
  voiceState.hearing = text;
  renderVoice();
  route(text, true);
}

const VOICE_LABELS = {
  listening: ['mic', 'Listening', 'is-on'],
  off: ['mic-off', 'Voice off', ''],
  denied: ['mic-off', 'Microphone blocked', 'is-warn'],
  unsupported: ['mic-off', 'No speech recognition here', 'is-warn'],
  error: ['mic', 'Voice problem', 'is-warn'],
};

const AGENT_LABELS = {
  idle: ['mic', 'Reconnecting to Voxide…', ''],
  connecting: ['mic', 'Connecting to Voxide…', ''],
  listening: ['mic', 'Voxide is listening', 'is-on'],
  armed: ['mic', 'Voxide is listening', 'is-on'],
  thinking: ['voice', 'Voxide is thinking', 'is-on'],
  speaking: ['voice', 'Voxide is speaking', 'is-on'],
  executing: ['voice', 'Voxide is acting', 'is-on'],
  error: ['mic', 'Voxide problem', 'is-warn'],
};

const listening = () => Boolean(agent.engine) || voice.listening;

function renderVoice() {
  const [ic, label, cls] = agent.engine
    ? AGENT_LABELS[agent.status] ?? AGENT_LABELS.connecting
    : VOICE_LABELS[voiceState.status] ?? VOICE_LABELS.error;
  const live = agent.engine ? agentLive() : voiceState.status === 'listening';
  const detail = agent.engine ? agent.error : voiceState.detail;
  for (const el of $$('[data-voice]')) {
    el.innerHTML = `
      <div class="voice__state ${cls}">${icon(ic)}<span>${label}</span>${live ? '<i class="dot dot--live"></i>' : ''}</div>
      <p class="voice__prompt">${esc(el.dataset.prompt)}</p>
      ${voiceState.hearing ? `<p class="voice__hearing" aria-live="polite">“${esc(voiceState.hearing)}”</p>` : ''}
      ${detail ? `<p class="notice">${icon('info')}<span>${esc(detail)}</span></p>` : ''}`;
  }
  $('#micBtn').innerHTML = listening() ? `${icon('stop')}Stop` : `${icon('mic')}Start listening`;
  $('#micBtn').className = listening() ? 'btn grow' : 'btn btn--ink grow';
  renderVoxideStatus();
  renderProtection();
}

function renderSeg(container, value, onPick, labels = LANG_SHORT) {
  container.innerHTML = LANGS.map(
    (l) => `<button type="button" data-lang="${l}" aria-pressed="${l === value}" aria-label="${LANG_LABELS[l]}">${labels[l]}</button>`,
  ).join('');
  container.onclick = (e) => {
    const b = e.target.closest('[data-lang]');
    if (b) onPick(b.dataset.lang);
  };
}

let listenLang = data.settings.language;
function renderListenLang() {
  renderSeg($('#listenLang'), listenLang, (l) => {
    listenLang = l;
    if (agent.engine) agent.engine.setLanguage(l);
    else voice.setLanguage(l);
    renderListenLang();
  });
}

$('#micBtn').addEventListener('click', () => {
  if (listening()) {
    agent.stopped = true;
    if (agent.engine) stopAgent();
    voice.stop();
  } else {
    agent.stopped = false;
    if (wantAgent()) {
      startAgent();
    } else {
      voice.setLanguage(listenLang);
      voice.start();
    }
  }
  renderVoice();
});
$('#typeForm').addEventListener('submit', (e) => {
  e.preventDefault();
  const text = $('#typeInput').value.trim();
  if (text) typed(text);
  $('#typeInput').value = '';
});
if (!voice.supported) {
  voiceState.status = 'unsupported';
  voiceState.detail = 'This browser has no speech recognition. Use Chrome or Edge, or type below.';
}

// ---------------------------------------------------------------- Voxide

// Voxide (voxide.app) is the voice layer: its agent hears the person and
// bystanders in Amharic, Afaan Oromo and English, speaks in a natural voice,
// and calls the app's capabilities (handleAgentTool). Shared engine:
// vendor/paziyon-voxide.js. Web Speech and the recorded clips are the
// fallback when there is no key or no connection. Only one engine holds the
// microphone.


const voxideKey = () => (data.settings.voxideKey ?? '').trim();
const voxideConfigured = () => voxideKey().startsWith('vox_pub_') && Boolean(window.PaziyonVoxide);
const agentLive = () => ['listening', 'armed', 'thinking', 'speaking', 'executing'].includes(agent.status);

// Voxide runs during every countdown and alert, and while idle when "listen
// with Voxide all the time" is on.
const wantAgent = () =>
  voxideConfigured() &&
  Boolean(data.profile.name) &&
  !agent.stopped &&
  (machine.state !== STATES.IDLE || data.settings.voxideAlwaysListen);

function startAgent() {
  if (voice.listening) voice.stop();
  try {
    agent.engine = window.PaziyonVoxide.create({ key: voxideKey(), language: listenLang, onEvent: onAgentEvent });
    agent.status = 'connecting';
    agent.error = null;
    pushAgentState();
    agent.engine.start();
  } catch (e) {
    agent.engine = null;
    agent.status = 'error';
    agent.error = e.message;
  }
  renderVoice();
}

function stopAgent() {
  agent.engine?.stop();
  agent.engine = null;
  agent.status = 'off';
  agentWaiters.forEach((w) => w('off'));
  renderVoice();
}

/** Starts or stops Voxide for the current state; Web Speech takes over without it. */
function syncVoice() {
  if (wantAgent()) {
    if (!agent.engine) startAgent();
  } else if (agent.engine) {
    stopAgent();
    if (!agent.stopped && voice.supported && data.settings.voiceTrigger) {
      voice.setLanguage(listenLang);
      voice.start();
    }
  }
  renderVoice();
}

async function agentSay(text, lang) {
  agent.reading++;
  try {
    return await agent.engine.say(text, lang);
  } finally {
    agent.reading--;
  }
}

function onAgentEvent(e) {
  switch (e.type) {
    case 'status':
      agent.status = e.status;
      if (agentLive()) agent.error = null;
      agentWaiters.forEach((w) => w(e.status));
      return renderVoice();
    case 'heard':
      return onAgentHeard(e.text ?? '', e.final);
    case 'said':
      // Answers to bystanders go in the conversation; read-aloud steps don't.
      if (machine.state === STATES.ACTIVE && !agent.reading && e.text?.trim()) addConvo('a', e.text);
      return;
    case 'tool':
      return agent.engine?.resolveTool(e.id, handleAgentTool(e.name, e.args ?? {}));
    case 'error':
      agent.error = e.message;
      return renderVoice();
  }
}

// Trigger and cancel are also matched here, as a backup to the agent's own
// tool calls (both are idempotent). During an alert the agent answers
// bystanders itself, so the first-aid loop just pauses for it.
function onAgentHeard(text, isFinal) {
  if (!agentInUtterance) {
    agentUtterance++;
    agentInUtterance = true;
  }
  const utterance = `voxide-${agentUtterance}`;
  if (isFinal) agentInUtterance = false;
  if (!text.trim()) return;
  voiceState.hearing = text.trim();
  renderVoice();
  switch (machine.state) {
    case STATES.IDLE:
    case STATES.COUNTDOWN:
      if (utterance !== actedOnUtterance && route(text, isFinal)) actedOnUtterance = utterance;
      return;
    case STATES.ACTIVE:
      if (isFinal) {
        addConvo('q', text);
        interrupt(waitForAgentToFinish);
      }
  }
}

/** Waits while the agent thinks, uses tools and answers (max 25 s). */
function waitForAgentToFinish() {
  return new Promise((resolve) => {
    let busy = !['listening', 'armed', 'off', 'error', 'idle'].includes(agent.status);
    const finish = () => {
      agentWaiters.delete(waiter);
      clearTimeout(quiet);
      clearTimeout(limit);
      resolve();
    };
    const waiter = (s) => {
      if (s === 'thinking' || s === 'speaking' || s === 'executing') busy = true;
      else if (busy || s === 'off' || s === 'error') finish();
    };
    agentWaiters.add(waiter);
    // If nothing starts within 4 s the agent chose not to answer.
    const quiet = setTimeout(() => !busy && finish(), 4000);
    const limit = setTimeout(finish, 25000);
  });
}

function alertStatus() {
  const snap = machine.snapshot();
  const status = { state: machine.state };
  if (machine.state === STATES.COUNTDOWN) status.secondsLeftToCancel = snap.remaining;
  if (machine.state === STATES.ACTIVE) {
    Object.assign(status, {
      secondsSinceAlert: snap.elapsed,
      description: ANSWERS.elapsed.en(Math.floor(snap.elapsed / 60), snap.elapsed % 60),
      longerThanFiveMinutes: snap.elapsed >= 300,
      currentFirstAidStep: loop.step + 1,
    });
  }
  status.contactsAlerted = machine.state === STATES.ACTIVE
    ? `${data.contacts.length} emergency contact(s); the SMS is sent from this phone`
    : 'not yet';
  return status;
}

/** What the agent sees on every turn. */
function pushAgentState() {
  if (!agent.engine) return;
  const snap = machine.snapshot();
  agent.engine.setState({
    appState: machine.state,
    secondsLeftToCancel: machine.state === STATES.COUNTDOWN ? snap.remaining : null,
    secondsSinceAlert: machine.state === STATES.ACTIVE ? snap.elapsed : null,
    firstAidStep: machine.state === STATES.ACTIVE ? loop.step + 1 : null,
    firstAidSteps: FIRST_AID_STEPS.en.length,
    patientName: data.profile.name,
    preferredLanguage: data.settings.language,
  });
}

/** Answers a Voxide capability call; the agent reads the result aloud. */
function handleAgentTool(name, args) {
  switch (name) {
    case 'start_emergency_alert':
      if (machine.state === STATES.IDLE && machine.trigger('voice')) {
        return {
          ok: true,
          message: `Countdown started. The alert goes to emergency contacts in ${data.settings.cancelWindowSeconds} seconds unless the person says they are okay.`,
        };
      }
      return { ok: true, message: 'An alert is already in progress.', ...alertStatus() };
    case 'cancel_alert':
      if (machine.state === STATES.COUNTDOWN && machine.cancel('voice')) return { ok: true, message: 'Cancelled. Nothing was sent.' };
      return {
        ok: false,
        message: machine.state === STATES.ACTIVE
          ? 'The alert was already sent. A bystander must hold the "Patient returned" button to stop it.'
          : 'No countdown is running.',
      };
    case 'get_alert_status':
      return { ok: true, ...alertStatus() };
    case 'get_first_aid_step': {
      const lang = LANGS.includes(args.language) ? args.language : loop.lang;
      const steps = FIRST_AID_STEPS[lang];
      if (args.which === 'next') loop.step = (loop.step + 1) % steps.length;
      loop.lang = lang;
      if (machine.state === STATES.ACTIVE) {
        renderStep();
        renderStepLang();
      }
      pushAgentState();
      return { ok: true, step: loop.step + 1, of: steps.length, language: lang, text: steps[loop.step] };
    }
    case 'get_medical_info':
      return {
        ok: true,
        ...data.profile,
        emergencyContacts: data.contacts.map((c) => `${c.name}${c.relationship ? ` (${c.relationship})` : ''}`),
      };
    case 'call_emergency_services':
      // Give the agent a moment to say so before the dialer opens.
      setTimeout(() => (location.href = `tel:${EMERGENCY_NUMBER}`), 2500);
      return { ok: true, message: `Calling ${EMERGENCY_NUMBER} now.` };
    default:
      return { ok: false, message: `Unknown capability ${name}.` };
  }
}

machine.subscribe((snap) => {
  if (snap.event !== 'tick' || snap.elapsed % 5 === 0) pushAgentState();
  if (snap.event === 'triggered' || snap.event === 'reset') syncVoice();
});

function renderVoxideStatus() {
  const el = $('#voxideStatus');
  if (!el) return;
  const key = voxideKey();
  el.textContent = !key
    ? 'Paste the publishable key from your Voxide dashboard. Without it the demo uses this browser’s speech recognition and recorded clips.'
    : !key.startsWith('vox_pub_')
      ? 'That is not a publishable key: it should start with vox_pub_.'
      : !window.PaziyonVoxide
        ? 'The Voxide SDK did not load.'
        : agent.engine
          ? `${(AGENT_LABELS[agent.status] ?? AGENT_LABELS.connecting)[1]}.${agent.error ? ` ${agent.error}` : ''}`
          : 'Voxide is ready. It starts with the next countdown, or with “Start listening”.';
}

// ---------------------------------------------------------------- hold buttons

function holdButton(button, ms, onComplete) {
  let timer = null;
  const start = (e) => {
    e.preventDefault();
    button.classList.add('holding');
    timer = setTimeout(() => {
      button.classList.remove('holding');
      timer = null;
      onComplete();
    }, ms);
  };
  const end = () => {
    button.classList.remove('holding');
    clearTimeout(timer);
    timer = null;
  };
  button.addEventListener('pointerdown', start);
  ['pointerup', 'pointerleave', 'pointercancel'].forEach((t) => button.addEventListener(t, end));
  // Keyboard and switch access: a click without a pointer fires immediately.
  button.addEventListener('click', (e) => {
    if (e.detail === 0) onComplete();
  });
  button.addEventListener('contextmenu', (e) => e.preventDefault());
}

holdButton($('#triggerBtn'), 800, () => machine.trigger('manual'));

// ---------------------------------------------------------------- fall detection

const STAGES = { monitor: 'Watching for falls', freefall: 'Freefall detected…', impact: 'Impact. Checking stillness…' };
const detector = createFallDetector({
  sensitivity: data.settings.sensitivity,
  onStage: (stage) => ($('#fallStage').textContent = STAGES[stage] ?? stage),
  onFall: () => machine.trigger('fall'),
});
const feedDetector = (sample) => {
  if (data.settings.fallDetection && machine.state === STATES.IDLE) detector.push(sample);
};

async function applyFallDetection() {
  if (data.settings.fallDetection) {
    const status = await startMotion(feedDetector);
    $('#fallStage').textContent = status === 'on' ? STAGES.monitor : 'No motion sensor here. Use Simulate.';
  } else {
    stopMotion();
    $('#fallStage').textContent = 'Off';
  }
  renderProtection();
}

$('#simulateFall').addEventListener('click', () => {
  if (!data.settings.fallDetection) {
    $('#fallStage').textContent = 'Turn on fall detection in Settings';
    return;
  }
  detector.reset();
  $('#simulateFall').disabled = true;
  $('#simulateFall').textContent = 'Simulating…';
  simulateFall(feedDetector, () => {
    $('#simulateFall').disabled = false;
    $('#simulateFall').textContent = 'Simulate a fall';
  });
});

// ---------------------------------------------------------------- countdown

let wakeLock = null;
async function keepScreenOn() {
  try {
    wakeLock = await navigator.wakeLock?.request('screen');
  } catch {}
}

function onTriggered(snap) {
  keepScreenOn();
  currentEvent = {
    id: String(snap.triggeredAt),
    time: snap.triggeredAt,
    trigger: snap.source,
    outcome: 'countdown',
    durationSeconds: 0,
    lat: lastLocation()?.lat ?? null,
    lng: lastLocation()?.lng ?? null,
    contactsNotified: 0,
  };
  const [ic, label] = SOURCES[snap.source];
  $('#countIcon').setAttribute('href', `#i-${ic}`);
  $('#countSource').textContent = label;
  voiceState.hearing = null;
  renderVoice();
  $('#countdown').hidden = false;
  $('#cancelBtn').focus();
  onCountdown(snap);
  // Voice cancel must work without a tap, so listen during the countdown
  // (Voxide when configured: see syncVoice).
  if (voxideConfigured()) {
    agent.stopped = false;
  } else if (voice.supported && !voice.listening) {
    voice.setLanguage(listenLang);
    voice.start();
  }
}

function onCountdown(snap) {
  const lang = data.settings.language;
  const total = data.settings.cancelWindowSeconds;
  $('#countNum').textContent = snap.remaining;
  $('#countText').textContent = COUNTDOWN_PROMPT[lang](snap.remaining);
  $('#countRing').style.strokeDashoffset = String(289 * (1 - snap.remaining / total));
  $('#countdown').style.setProperty('--heat', String(1 - snap.remaining / total));
  navigator.vibrate?.(200);
  if (snap.remaining === total || snap.remaining === 10 || snap.remaining === 5) {
    speak(COUNTDOWN_PROMPT[lang](snap.remaining), lang, `countdown-${snap.remaining}`);
  }
}

$('#cancelBtn').addEventListener('click', () => machine.cancel('tap'));

// ---------------------------------------------------------------- bystander mode

const loop = { gen: 0, step: 0, lang: data.settings.languageOrder[0], cycle: true };

function onActivated(snap) {
  stopSpeaking();
  navigator.vibrate?.(0);
  $('#countdown').hidden = true;

  const loc = lastLocation();
  alertInfo = {
    status: 'active',
    trigger: snap.source,
    time: snap.activatedAt,
    lat: loc?.lat ?? null,
    lng: loc?.lng ?? null,
    profile: data.profile,
  };
  Object.assign(currentEvent, { outcome: 'active', lat: alertInfo.lat, lng: alertInfo.lng, contactsNotified: data.contacts.length });
  saveEvent();

  const dashUrl = dashboardUrl(alertInfo);
  $('#dashLink').href = dashUrl;
  $('#smsBtn').href = smsHref(smsBody(alertInfo, dashUrl, APP_NAME));
  $('#smsBtn span').textContent = data.contacts.length
    ? `Send alert SMS to ${data.contacts.length} contact${data.contacts.length > 1 ? 's' : ''}`
    : 'Send alert SMS (pick a recipient)';
  $('#callBtn').href = `tel:${EMERGENCY_NUMBER}`;

  $('#emHeader').innerHTML = LANGS.map((l) => `<span lang="${l}">${esc(EMERGENCY_HEADER[l])}</span>`).join('');
  $('#bystanderMedical').innerHTML = medicalCard(data.profile);
  $('#convo').innerHTML = '';
  voiceState.hearing = null;
  renderVoice();
  $('#bystander').hidden = false;
  $('#bystander').scrollTop = 0;

  loop.step = 0;
  loop.cycle = true;
  loop.lang = data.settings.languageOrder[0];
  loop.sirenIntroDone = false;
  loop.sirenMuted = false;
  renderSirenBtn();
  renderStepLang();
  renderElapsed(0);
  runLoop();
}

function renderElapsed(seconds) {
  const m = Math.floor(seconds / 60);
  const s = String(seconds % 60).padStart(2, '0');
  $('#elapsed').textContent = `${m}:${s}`;
  $('.em-timer').classList.toggle('late', seconds >= 300);
}

function renderStep() {
  const steps = FIRST_AID_STEPS[loop.lang];
  $('#stepCount').textContent = `Step ${loop.step + 1} of ${steps.length}`;
  $('#stepText').textContent = steps[loop.step];
  $('#stepText').lang = loop.lang;
  $('#stepDots').innerHTML = steps.map((_, i) => `<li class="${i <= loop.step ? 'on' : ''}"></li>`).join('');
}

function renderStepLang() {
  renderSeg($('#stepLang'), loop.lang, (l) => {
    loop.cycle = false;
    loop.lang = l;
    renderStepLang();
    interrupt(async () => {});
  });
  $('#cycleBtn span').textContent = loop.cycle ? 'Cycling all languages' : 'Cycle all languages';
  $('#cycleBtn').disabled = loop.cycle;
}
$('#cycleBtn').addEventListener('click', () => {
  loop.cycle = true;
  renderStepLang();
});

// Loops the first-aid steps, one language after another, until the alert ends.
// Bumping loop.gen stops the current run (used to interrupt for an answer).
const sirenWanted = () => data.settings.siren && !loop.sirenMuted;

async function runLoop() {
  const gen = ++loop.gen;
  // A loud siren first draws people over, then the instructions start.
  if (sirenWanted() && !loop.sirenIntroDone) {
    loop.sirenIntroDone = true;
    renderStep();
    await sirenBurst(6000);
    if (gen !== loop.gen) return;
  }
  while (gen === loop.gen && machine.state === STATES.ACTIVE) {
    renderStep();
    await speak(FIRST_AID_STEPS[loop.lang][loop.step], loop.lang, `step-${loop.step + 1}`);
    if (gen !== loop.gen) return;
    if (sirenWanted()) {
      await sirenBurst(3000);
      if (gen !== loop.gen) return;
    }
    // A pause between steps is when a bystander can most easily be heard.
    await sleep(1800);
    if (gen !== loop.gen) return;
    loop.step = (loop.step + 1) % FIRST_AID_STEPS.en.length;
    if (loop.step === 0 && loop.cycle) {
      const order = data.settings.languageOrder;
      loop.lang = order[(order.indexOf(loop.lang) + 1) % order.length];
      renderStepLang();
    }
  }
}

async function interrupt(fn) {
  loop.gen++;
  stopSpeaking();
  // Quiet the siren so the bystander and the phone can hear each other.
  if (sirenPlaying()) stopSiren();
  await fn();
  if (machine.state === STATES.ACTIVE) {
    await sleep(800);
    runLoop();
  }
}

function answerBystander(match) {
  const lang = match?.lang ?? loop.lang;
  // `clip` plays the recorded Amharic/Oromo audio; `spoken` is what to say
  // when it differs from the text shown.
  const reply = (msg, clip, spoken) => {
    addConvo('a', msg);
    return speak(spoken ?? msg, lang, clip);
  };
  interrupt(async () => {
    if (!match) return reply(ANSWERS.notUnderstood[lang], 'answer-notUnderstood');
    switch (match.intent) {
      case INTENTS.ELAPSED: {
        const secs = machine.snapshot().elapsed;
        // Clips exist per whole minute; the exact time is shown on screen.
        const minutes = Math.min(30, Math.floor(secs / 60));
        await reply(
          ANSWERS.elapsed[lang](Math.floor(secs / 60), secs % 60),
          `elapsed-${minutes}`,
          lang === 'en' ? undefined : ELAPSED_SPOKEN[lang](minutes),
        );
        if (secs >= 300) await reply(ANSWERS.overFiveMinutes[lang], 'answer-overFiveMinutes');
        return;
      }
      case INTENTS.WHAT_TO_DO:
      case INTENTS.REPEAT:
        loop.lang = lang;
        renderStep();
        return reply(FIRST_AID_STEPS[lang][loop.step], `step-${loop.step + 1}`);
      case INTENTS.NEXT_STEP:
        loop.lang = lang;
        loop.step = (loop.step + 1) % FIRST_AID_STEPS.en.length;
        renderStep();
        return reply(FIRST_AID_STEPS[lang][loop.step], `step-${loop.step + 1}`);
      case INTENTS.CALL_HELP:
        await reply(ANSWERS.calling[lang], 'answer-calling');
        location.href = `tel:${EMERGENCY_NUMBER}`;
        return;
      case INTENTS.MEDICAL_INFO:
        return reply(ANSWERS.medical[lang](data.profile));
      case INTENTS.CANCEL:
        return reply(ANSWERS.holdToStop[lang], 'answer-holdToStop');
    }
  });
}

function renderSirenBtn() {
  $('#sirenBtn').hidden = !data.settings.siren || loop.sirenMuted;
}
$('#sirenBtn').addEventListener('click', () => {
  loop.sirenMuted = true;
  stopSiren();
  renderSirenBtn();
});

function addConvo(kind, text) {
  const li = document.createElement('li');
  li.className = kind;
  li.textContent = text;
  $('#convo').prepend(li);
  while ($('#convo').children.length > 6) $('#convo').lastChild.remove();
}

$('#askForm').addEventListener('submit', (e) => {
  e.preventDefault();
  const text = $('#askInput').value.trim();
  if (text) typed(text);
  $('#askInput').value = '';
});

holdButton($('#stopBtn'), 2000, () => machine.resolve('tap'));

// ---------------------------------------------------------------- resolution

function onFinished(snap) {
  loop.gen++;
  stopSpeaking();
  stopSiren();
  if (agentLive()) agent.engine.interrupt();
  navigator.vibrate?.(0);
  wakeLock?.release?.();
  $('#countdown').hidden = true;
  $('#bystander').hidden = true;

  currentEvent.outcome = snap.outcome;
  currentEvent.durationSeconds = snap.activatedAt ? Math.round((snap.resolvedAt - snap.activatedAt) / 1000) : 0;
  saveEvent();

  const cancelled = snap.outcome === 'cancelled';
  $('#resolvedTitle').textContent = cancelled ? 'Alert cancelled' : 'Alert resolved';
  $('#resolvedText').textContent = cancelled
    ? `Cancelled by ${snap.resolvedBy === 'voice' ? 'voice' : 'tap'} before anything was sent.`
    : `Alert lasted ${formatDuration(currentEvent.durationSeconds)}. Let your contacts know you are okay.`;
  const okay = $('#okaySms');
  okay.hidden = cancelled;
  if (!cancelled) {
    const resolved = { ...alertInfo, status: 'resolved' };
    okay.href = smsHref(smsBody(resolved, dashboardUrl(resolved), APP_NAME));
  }
  $('#resolved').hidden = false;
}

$('#resolvedDone').addEventListener('click', () => machine.reset());

function onReset() {
  $('#resolved').hidden = true;
  currentEvent = null;
  alertInfo = null;
  voiceState.hearing = null;
  detector.reset();
  renderAll();
}

// ---------------------------------------------------------------- links

function dashboardUrl(alert) {
  return new URL(`dashboard.html#${encodeAlert(alert)}`, location.href).href;
}

// "?&body=" works on both Android and iOS.
function smsHref(body) {
  const to = data.contacts.map((c) => c.phone.replace(/[^\d+]/g, '')).join(',');
  return `sms:${to}?&body=${encodeURIComponent(body)}`;
}

// ---------------------------------------------------------------- views

function medicalCard(p) {
  const rows = [
    ['Name', p.name], ['Condition', p.condition], ['Seizure type', p.seizureType],
    ['Medications', p.medications], ['Allergies', p.allergies], ['Blood type', p.bloodType],
    ...data.contacts.map((c) => ['Contact', `${c.name}${c.relationship ? ` (${c.relationship})` : ''} · ${c.phone}`]),
  ].filter(([, v]) => v);
  return `<div class="medical"><h3>${icon('medical')}MEDICAL ID</h3><dl>${
    rows.map(([k, v]) => `<dt>${k}</dt><dd>${esc(v)}</dd>`).join('') || '<dt></dt><dd class="muted">No medical details yet</dd>'
  }</dl></div>`;
}

function formatDuration(s) {
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`;
}

function timeAgo(t) {
  const d = Math.floor((Date.now() - t) / 1000);
  if (d < 60) return 'just now';
  if (d < 3600) return `${Math.floor(d / 60)} min ago`;
  if (d < 86400) return `${Math.floor(d / 3600)} h ago`;
  return `${Math.floor(d / 86400)} days ago`;
}

function renderProtection() {
  const on = data.settings.fallDetection || listening();
  $('#protection').innerHTML = `<i class="dot ${on ? 'dot--live' : 'dot--warn'}"></i><span>${on ? 'Protected' : 'Paused'}</span>`;
}

function renderHome() {
  const n = data.contacts.length;
  $('#contactsTitle').textContent = `${n} emergency contact${n === 1 ? '' : 's'}`;
  $('#contactsSub').textContent = n ? data.contacts.map((c) => c.name).join(', ') : 'Add someone who should get the SMS';
  const last = data.events[0];
  $('#lastEvent').textContent = last ? `Last event ${timeAgo(last.time)}` : 'No events yet';
  renderProtection();
}

const OUTCOMES = { cancelled: 'Cancelled', resolved: 'Alert sent, resolved', active: 'Alert sent', countdown: 'Countdown' };
const TRIGGERS = { voice: 'Voice', manual: 'Button', fall: 'Fall detected' };

function renderHistory() {
  const list = $('#historyList');
  if (!data.events.length) {
    list.innerHTML = `<div class="empty">${icon('history')}<b>No events yet</b><p class="muted">Alerts and cancelled countdowns will appear here.</p></div>`;
    return;
  }
  list.innerHTML = `<div class="group">${data.events
    .map((e) => {
      const map = mapLink(e.lat, e.lng);
      const meta = [
        new Date(e.time).toLocaleString(),
        TRIGGERS[e.trigger] ?? e.trigger,
        e.durationSeconds ? formatDuration(e.durationSeconds) : null,
        `${e.contactsNotified} contact${e.contactsNotified === 1 ? '' : 's'}`,
      ].filter(Boolean).join(' · ');
      return `<div class="row2">${icon(SOURCES[e.trigger]?.[0] ?? 'info', 'icon row2__icon')}
        <span class="row2__text"><b>${OUTCOMES[e.outcome] ?? e.outcome}</b><span class="muted">${esc(meta)}${
          map ? ` · <a href="${map}" target="_blank" rel="noopener">map</a>` : ''}</span></span>
        ${e.outcome === 'cancelled' ? '' : '<i class="badge-dot" aria-label="Alert was sent"></i>'}</div>`;
    })
    .join('')}</div>`;
}

function saveEvent() {
  const i = data.events.findIndex((e) => e.id === currentEvent.id);
  if (i >= 0) data.events[i] = { ...currentEvent };
  else data.events.unshift({ ...currentEvent });
  persist();
}

$('#exportCsv').addEventListener('click', () => {
  const cols = ['time', 'trigger', 'outcome', 'durationSeconds', 'lat', 'lng', 'contactsNotified'];
  const rows = data.events.map((e) => cols.map((c) => (c === 'time' ? new Date(e.time).toISOString() : e[c] ?? '')).join(','));
  const blob = new Blob([[cols.join(','), ...rows].join('\n')], { type: 'text/csv' });
  const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: 'paziyon-history.csv' });
  a.click();
  URL.revokeObjectURL(a.href);
});

// Medical ID form
const profileForm = $('#profileForm');
function fillProfileForm() {
  for (const [k, v] of Object.entries(data.profile)) if (profileForm.elements[k]) profileForm.elements[k].value = v;
  $('#medicalPreview').innerHTML = medicalCard(data.profile);
}
profileForm.addEventListener('input', () => {
  for (const el of profileForm.elements) if (el.name) data.profile[el.name] = el.value.trim();
  persist();
  $('#medicalPreview').innerHTML = medicalCard(data.profile);
});

// Settings form
const settingsForm = $('#settingsForm');
function fillSettingsForm() {
  const s = data.settings;
  settingsForm.elements.cancelWindowSeconds.value = s.cancelWindowSeconds;
  $('#cancelWindowOut').textContent = s.cancelWindowSeconds;
  settingsForm.elements.voiceTrigger.checked = s.voiceTrigger;
  settingsForm.elements.fallDetection.checked = s.fallDetection;
  settingsForm.elements.sensitivity.value = s.sensitivity;
  settingsForm.elements.siren.checked = s.siren;
  settingsForm.elements.voxideKey.value = s.voxideKey;
  settingsForm.elements.voxideAlwaysListen.checked = s.voxideAlwaysListen;
  renderVoxideStatus();
  renderSeg($('#promptLang'), s.language, (l) => {
    data.settings.language = l;
    persist();
    fillSettingsForm();
  });
}
settingsForm.addEventListener('input', (e) => {
  const f = settingsForm.elements;
  if (e.target === f.voxideKey) return renderVoxideStatus(); // applied on change, not per keystroke
  const fallChanged = f.fallDetection.checked !== data.settings.fallDetection;
  const modeChanged = f.voxideAlwaysListen.checked !== data.settings.voxideAlwaysListen;
  Object.assign(data.settings, {
    cancelWindowSeconds: Number(f.cancelWindowSeconds.value),
    voiceTrigger: f.voiceTrigger.checked,
    fallDetection: f.fallDetection.checked,
    sensitivity: f.sensitivity.value,
    siren: f.siren.checked,
    voxideAlwaysListen: f.voxideAlwaysListen.checked,
  });
  if (!data.settings.siren) stopSiren();
  if (modeChanged) syncVoice();
  $('#cancelWindowOut').textContent = data.settings.cancelWindowSeconds;
  machine.setCancelWindow(data.settings.cancelWindowSeconds);
  detector.setSensitivity(data.settings.sensitivity);
  if (fallChanged) applyFallDetection();
  persist();
});

settingsForm.elements.voxideKey.addEventListener('change', (e) => {
  const key = e.target.value.trim();
  if (key === data.settings.voxideKey) return;
  data.settings.voxideKey = key;
  persist();
  // Reconnect with the new key.
  if (agent.engine) stopAgent();
  agent.stopped = false;
  syncVoice();
});

// Contacts
function renderContacts() {
  $('#contactList').innerHTML = data.contacts
    .map(
      (c, i) => `<div class="row2">${icon('person', 'icon row2__icon')}
        <span class="row2__text"><b>${esc(c.name)}</b><span class="muted">${esc([c.phone, c.relationship].filter(Boolean).join(' · '))}</span></span>
        <button class="icon-btn" data-remove="${i}" aria-label="Remove ${esc(c.name)}">${icon('close')}</button></div>`,
    )
    .join('');
  $('#contactList').hidden = !data.contacts.length;
  $('#contactCount').textContent = `· ${data.contacts.length}/5`;
  $('#contactForm').hidden = data.contacts.length >= 5;
  renderHome();
}
$('#contactList').addEventListener('click', (e) => {
  const i = e.target.closest('[data-remove]')?.dataset.remove;
  if (i === undefined) return;
  data.contacts.splice(Number(i), 1);
  persist();
  renderContacts();
});
$('#contactForm').addEventListener('submit', (e) => {
  e.preventDefault();
  const f = e.target.elements;
  data.contacts.push({ name: f.name.value.trim(), phone: f.phone.value.trim(), relationship: f.relationship.value.trim() });
  persist();
  e.target.reset();
  renderContacts();
});

function loadDemoProfile(lang) {
  data.profile = { ...DEMO_PROFILES[lang] };
  data.settings.language = lang;
  // Start the instruction loop in the chosen language.
  data.settings.languageOrder = [lang, ...LANGS.filter((l) => l !== lang)];
  listenLang = lang;
  persist();
  fillProfileForm();
  fillSettingsForm();
  renderListenLang();
}

$('#loadDemo').addEventListener('click', () => loadDemoProfile(data.settings.language));
$('#deleteAll').addEventListener('click', () => {
  if (!confirm('Delete profile, contacts, settings and history from this device?')) return;
  store.clear();
  location.reload();
});

// Tabs, and rows that jump to a tab
function openTab(name) {
  $$('.tabs button').forEach((x) => (x.dataset.tab === name ? x.setAttribute('aria-current', 'page') : x.removeAttribute('aria-current')));
  $$('.view').forEach((v) => (v.hidden = v.dataset.view !== name));
  if (name === 'history') renderHistory();
  scrollTo(0, 0);
}
$$('.tabs button').forEach((b) => b.addEventListener('click', () => openTab(b.dataset.tab)));
$$('[data-go]').forEach((b) => b.addEventListener('click', () => openTab(b.dataset.go)));

// Welcome (first launch)
if (!data.profile.name) $('#welcome').hidden = false;
$$('#welcome [data-lang]').forEach((b) =>
  b.addEventListener('click', () => {
    loadDemoProfile(b.dataset.lang);
    $('#welcome').hidden = true;
    renderContacts();
    agent.stopped = false;
    if (wantAgent()) {
      startAgent();
    } else if (voice.supported) {
      voice.setLanguage(b.dataset.lang);
      voice.start();
    }
    renderVoice();
  }),
);

// ---------------------------------------------------------------- start

function renderAll() {
  renderContacts();
  renderHistory();
  renderVoice();
  renderListenLang();
}

fillProfileForm();
fillSettingsForm();
renderAll();
startLocation();
applyFallDetection();
// Browsers only let a page play sound after a tap, so Voxide starts on the first one.
if (wantAgent()) document.addEventListener('pointerdown', () => !listening() && syncVoice(), { once: true, capture: true });
