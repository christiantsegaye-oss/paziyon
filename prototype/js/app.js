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
    await say(text, lang, clipName);
  } finally {
    entry.until = Date.now() + ECHO_WINDOW_MS;
  }
}
const recentlySpoken = () => spoken.filter((e) => e.until > Date.now()).map((e) => e.text);

// ---------------------------------------------------------------- voice input

const voiceState = { status: 'off', detail: null, hearing: null };
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

function renderVoice() {
  const [ic, label, cls] = VOICE_LABELS[voiceState.status] ?? VOICE_LABELS.error;
  for (const el of $$('[data-voice]')) {
    el.innerHTML = `
      <div class="voice__state ${cls}">${icon(ic)}<span>${label}</span>${voiceState.status === 'listening' ? '<i class="dot dot--live"></i>' : ''}</div>
      <p class="voice__prompt">${esc(el.dataset.prompt)}</p>
      ${voiceState.hearing ? `<p class="voice__hearing" aria-live="polite">“${esc(voiceState.hearing)}”</p>` : ''}
      ${voiceState.detail ? `<p class="notice">${icon('info')}<span>${esc(voiceState.detail)}</span></p>` : ''}`;
  }
  $('#micBtn').innerHTML = voice.listening ? `${icon('stop')}Stop` : `${icon('mic')}Start listening`;
  $('#micBtn').className = voice.listening ? 'btn grow' : 'btn btn--ink grow';
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
    voice.setLanguage(l);
    renderListenLang();
  });
}

$('#micBtn').addEventListener('click', () => {
  if (voice.listening) {
    voice.stop();
  } else {
    voice.setLanguage(listenLang);
    voice.start();
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
  // Voice cancel must work without a tap, so listen during the countdown.
  if (voice.supported && !voice.listening) {
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
async function runLoop() {
  const gen = ++loop.gen;
  while (gen === loop.gen && machine.state === STATES.ACTIVE) {
    renderStep();
    await speak(FIRST_AID_STEPS[loop.lang][loop.step], loop.lang, `step-${loop.step + 1}`);
    if (gen !== loop.gen) return;
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
  const on = data.settings.fallDetection || voice.listening;
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
  renderSeg($('#promptLang'), s.language, (l) => {
    data.settings.language = l;
    persist();
    fillSettingsForm();
  });
}
settingsForm.addEventListener('input', () => {
  const f = settingsForm.elements;
  const fallChanged = f.fallDetection.checked !== data.settings.fallDetection;
  Object.assign(data.settings, {
    cancelWindowSeconds: Number(f.cancelWindowSeconds.value),
    voiceTrigger: f.voiceTrigger.checked,
    fallDetection: f.fallDetection.checked,
    sensitivity: f.sensitivity.value,
  });
  $('#cancelWindowOut').textContent = data.settings.cancelWindowSeconds;
  machine.setCancelWindow(data.settings.cancelWindowSeconds);
  detector.setSensitivity(data.settings.sensitivity);
  if (fallChanged) applyFallDetection();
  persist();
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
    if (voice.supported) {
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
