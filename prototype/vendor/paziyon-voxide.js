/*
 * P.A.Z.I.Y.O.N ↔ Voxide.
 *
 * Voxide (voxide.app) is the voice layer the hackathon requires. Its agent
 * listens and speaks naturally in Amharic, Afaan Oromo and English, and calls
 * the app's capabilities registered below. Shared, unchanged, by the web demo
 * (prototype/vendor/) and by the Android app, which runs it in a hidden
 * WebView (app/assets/voxide/bridge.html).
 *
 * Needs the Voxide browser SDK loaded first (window.Voxide, vendored as
 * voxide.browser.js) and a publishable key ("vox_pub_…") from the Voxide
 * dashboard.
 *
 * Events sent to onEvent:
 *   { type: 'status', status }          idle | connecting | listening | thinking | speaking | executing | error
 *   { type: 'heard', text, final }      what the person is saying (live)
 *   { type: 'said', text }              what the agent said (finished turn)
 *   { type: 'tool', id, name, args }    a capability call; answer with engine.resolveTool(id, result)
 *   { type: 'error', message }
 */
(function (global) {
  'use strict';

  var LANG_NAMES = { am: 'Amharic', om: 'Afaan Oromo', en: 'English' };
  var LANG_TAGS = { am: 'am-ET', om: 'om-ET', en: 'en-US' };

  // Sent with every turn (bindState), so the agent behaves the same whatever
  // prompt is set in the dashboard.
  var INSTRUCTIONS =
    'You are P.A.Z.I.Y.O.N, the emergency voice of a seizure and fall alert app in Ethiopia. ' +
    'Reply in the language the person speaks: Amharic, Afaan Oromo or English. ' +
    'Keep every reply to one or two short, calm sentences. ' +
    'If anyone asks for help or sounds unwell, call start_emergency_alert at once. ' +
    'During the countdown, if the person says they are fine, call cancel_alert. ' +
    'During an alert you are talking to bystanders: use get_first_aid_step, get_alert_status, ' +
    'get_medical_info and call_emergency_services, and read the results aloud. ' +
    'Never give medical advice beyond the first-aid steps the app returns.';

  var TOOLS = {
    start_emergency_alert: {
      description:
        'Start the emergency alert countdown. Call immediately when the user asks for help or says they feel a ' +
        'seizure, fall, faint or are unwell, in any language: "help", "እርዳታ", "እርዱኝ", "ድረሱልኝ", "Na gargaari", ' +
        '"gargaarsa". Do not ask for confirmation: the app gives them time to cancel.',
      params: { reason: { type: 'string', description: 'What the user said, briefly.' } },
    },
    cancel_alert: {
      description:
        'Cancel the countdown because the person says they are fine: "I am okay", "ደህና ነኝ", "Nagaan jira", ' +
        '"false alarm", "stop". Only works during the countdown.',
    },
    get_alert_status: {
      description:
        'Current state of the emergency: how many seconds it has been going on, the current first-aid step, ' +
        'and whether contacts were alerted. Use it to answer "how long has it been?".',
    },
    get_first_aid_step: {
      description: 'Get a first-aid instruction to read aloud to a bystander.',
      params: {
        which: { type: 'string', enum: ['current', 'next', 'repeat'], description: '"next" moves to the next step.' },
        language: { type: 'string', enum: ['am', 'om', 'en'], description: 'Language the bystander is speaking.' },
      },
    },
    get_medical_info: {
      description: "The patient's medical ID (name, condition, medications, allergies, blood type) for bystanders or paramedics.",
    },
    call_emergency_services: {
      description: 'Phone the ambulance (907) now. Use when a bystander asks to call for help, or the seizure has lasted more than 5 minutes.',
    },
  };

  function create(opts) {
    if (!global.Voxide || !global.Voxide.VoxideClient) throw new Error('Voxide SDK not loaded');
    var onEvent = opts.onEvent || function () {};
    var language = opts.language || 'en';
    var client = new global.Voxide.VoxideClient({
      publicKey: opts.key,
      baseUrl: opts.baseUrl || undefined,
      language: LANG_TAGS[language],
    });
    client.enableMultilingual({ mode: 'adaptive', supported: [LANG_TAGS.am, LANG_TAGS.om, LANG_TAGS.en] });

    var appState = {};
    client.bindState(function () {
      var s = { instructions: INSTRUCTIONS };
      for (var k in appState) s[k] = appState[k];
      return s;
    });

    // Every capability is answered by the host app (web page or Flutter).
    var nextId = 1;
    var pending = {};
    var actions = {};
    Object.keys(TOOLS).forEach(function (name) {
      var def = TOOLS[name];
      actions[name] = {
        description: def.description,
        params: def.params || {},
        handler: function (args) {
          return new Promise(function (resolve) {
            var id = nextId++;
            var timer = setTimeout(function () {
              delete pending[id];
              resolve({ ok: false, message: 'The app did not respond in time.' });
            }, 8000);
            pending[id] = function (result) {
              clearTimeout(timer);
              resolve(result);
            };
            onEvent({ type: 'tool', id: id, name: name, args: args || {} });
          });
        },
      };
    });
    client.register(actions);

    // ---- status, transcripts, errors
    var status = 'idle';
    var statusWaiters = [];
    client.on('status', function (s) {
      status = s;
      onEvent({ type: 'status', status: s });
      statusWaiters.slice().forEach(function (w) { w(s); });
    });
    client.on('message', function (m) {
      if (!m || !m.text) return;
      if (m.role === 'user') onEvent({ type: 'heard', text: m.text, final: true });
      else onEvent({ type: 'said', text: m.text });
    });
    var lastPartial = '';
    client.subscribe(function () {
      var msgs = client.getSnapshot().messages || [];
      var last = msgs[msgs.length - 1];
      if (last && last.role === 'user' && last.partial && last.text !== lastPartial) {
        lastPartial = last.text;
        onEvent({ type: 'heard', text: last.text, final: false });
      }
    });

    // ---- keep the session alive while wanted (sessions end on idle/time limits)
    var wanted = false;
    var retryMs = 2000;
    var retryTimer = null;
    var stopReason = null;
    client.on('error', function (message) {
      var text = String((message && message.message) || message || 'Voxide error');
      if (text === 'usage_limit') {
        stopReason = 'usage_limit';
        wanted = false;
        text = 'The Voxide plan has run out of voice sessions. Top it up in the Voxide dashboard.';
      }
      onEvent({ type: 'error', message: text });
    });
    client.on('status', function (s) {
      if (!wanted || (s !== 'idle' && s !== 'error')) {
        if (s === 'listening') retryMs = 2000;
        return;
      }
      clearTimeout(retryTimer);
      retryTimer = setTimeout(function () { if (wanted) connect(); }, retryMs);
      retryMs = Math.min(retryMs * 2, 30000);
    });

    function connect() {
      return client.init().then(function () { return client.connect(); }).catch(function (e) {
        onEvent({ type: 'error', message: (e && e.message) || 'Could not reach Voxide.' });
        onEvent({ type: 'status', status: 'error' });
        if (wanted) {
          clearTimeout(retryTimer);
          retryTimer = setTimeout(function () { if (wanted) connect(); }, retryMs);
          retryMs = Math.min(retryMs * 2, 30000);
        }
      });
    }

    // Resolves once the agent has finished speaking (or after a time limit).
    function waitUntilSpoken(maxMs) {
      return new Promise(function (resolve) {
        var spoke = false;
        var done = function () {
          clearTimeout(timer);
          statusWaiters = statusWaiters.filter(function (w) { return w !== waiter; });
          resolve();
        };
        var waiter = function (s) {
          if (s === 'speaking') spoke = true;
          else if (spoke && (s === 'listening' || s === 'idle' || s === 'error')) done();
        };
        var timer = setTimeout(done, maxMs);
        statusWaiters.push(waiter);
      });
    }

    return {
      start: function () {
        wanted = true;
        stopReason = null;
        return connect();
      },
      stop: function () {
        wanted = false;
        clearTimeout(retryTimer);
        client.disconnect();
      },
      get status() { return status; },
      get stopReason() { return stopReason; },
      setLanguage: function (lang) {
        language = lang;
        client.setLanguage(LANG_TAGS[lang] || LANG_TAGS.en);
      },
      setState: function (s) { appState = s || {}; },
      resolveTool: function (id, result) {
        var fn = pending[id];
        delete pending[id];
        if (fn) fn(result);
      },
      // Has the agent read text aloud, word for word, in a natural voice.
      say: function (text, lang) {
        if (status !== 'listening' && status !== 'speaking' && status !== 'thinking') return Promise.resolve(false);
        var name = LANG_NAMES[lang] || LANG_NAMES.en;
        var spoken = waitUntilSpoken(Math.min(30000, 6000 + text.length * 120));
        return client
          .sendText('[APP] Read this aloud to the people nearby, word for word, in ' + name + '. Say nothing else. "' + text + '"')
          .then(function () { return spoken; })
          .then(function () { return true; }, function () { return false; });
      },
      interrupt: function () { client.interrupt(); },
      inputLevel: function () { return client.getInputLevel(); },
    };
  }

  global.PaziyonVoxide = { create: create, TOOLS: TOOLS, INSTRUCTIONS: INSTRUCTIONS };
})(typeof window !== 'undefined' ? window : globalThis);
