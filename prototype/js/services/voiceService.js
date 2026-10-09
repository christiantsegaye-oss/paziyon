// VoiceService: one listening pipeline that feeds what it hears to the intent
// router. The engine is swappable. The real app plugs in Voxide here; this demo
// uses the browser's Web Speech API (Chrome/Edge), plus a typed-phrase
// fallback for browsers without it or a noisy room.
//
// What matters in practice:
//  - Interim results are passed on, so "help" acts the moment it is said
//    instead of after the browser decides the sentence is over.
//  - Each utterance has an id, so the app can act once per utterance.
//  - If the browser can't recognize the chosen language (Afaan Oromo in
//    Chrome), it falls back to English and says so instead of hearing nothing.

import { LANG_TAGS, LANG_LABELS } from '../core/content.js';

export function createVoiceService({ onHeard, onStatus = () => {} }) {
  const Recognition = globalThis.SpeechRecognition || globalThis.webkitSpeechRecognition;
  let recognition = null;
  let wanted = false;
  let lang = 'en';
  let tag = LANG_TAGS.en;
  let session = 0;
  let detail = null;

  const supported = Boolean(Recognition);
  const status = (s, why = detail) => {
    detail = why;
    onStatus(s, detail);
  };

  function start() {
    if (!supported) {
      status('unsupported', 'This browser has no speech recognition. Use Chrome or Edge, or type below.');
      return;
    }
    wanted = true;
    recognition?.abort();
    recognition = new Recognition();
    recognition.lang = tag;
    recognition.continuous = true;
    recognition.interimResults = true;
    const id = ++session;
    recognition.onresult = (e) => {
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i];
        onHeard({ text: r[0].transcript, isFinal: r.isFinal, utterance: `${id}:${i}` });
      }
    };
    recognition.onstart = () => status('listening');
    recognition.onerror = (e) => {
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed') {
        wanted = false;
        status('denied', 'Microphone permission is blocked. Allow it from the icon in the address bar.');
      } else if (e.error === 'language-not-supported' && tag !== LANG_TAGS.en) {
        tag = LANG_TAGS.en;
        status('error', `${LANG_LABELS[lang]} recognition isn't available in this browser, so it listens in English. You can still type ${LANG_LABELS[lang]} phrases.`);
      } else if (e.error === 'network') {
        status('error', 'Speech recognition needs an internet connection in this browser.');
      } else if (e.error === 'audio-capture') {
        status('error', 'No microphone found.');
      }
      // no-speech / aborted are normal; onend restarts.
    };
    // Chrome ends recognition after a pause; restart to keep listening.
    recognition.onend = () => {
      if (wanted) setTimeout(() => wanted && start(), 250);
    };
    try {
      recognition.start();
    } catch {
      status('error', 'Could not start listening. Try again.');
    }
  }

  function stop() {
    wanted = false;
    recognition?.abort();
    recognition = null;
    status('off', null);
  }

  return {
    supported,
    get listening() {
      return wanted;
    },
    start,
    stop,
    setLanguage(next) {
      lang = next;
      tag = LANG_TAGS[next];
      detail = null;
      if (wanted) start();
    },
  };
}
