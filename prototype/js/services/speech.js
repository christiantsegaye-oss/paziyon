// Spoken output. Plays a recorded clip from audio/<lang>/<name>.mp3 when one
// exists (the real app ships the CEE-reviewed recordings), otherwise falls back
// to the browser's text-to-speech if it has a voice for the language. If
// neither is available the text is only shown on screen.

import { LANG_TAGS } from '../core/content.js';

let current = null;
let endPause = null; // ends a text-only "reading pause" early when stopped
const missingClips = new Set();

function findVoice(lang) {
  const tag = LANG_TAGS[lang].toLowerCase();
  const voices = globalThis.speechSynthesis?.getVoices() ?? [];
  return (
    voices.find((v) => v.lang.toLowerCase() === tag) ||
    voices.find((v) => v.lang.toLowerCase().startsWith(tag.slice(0, 2)))
  );
}

export function canSpeak(lang) {
  return Boolean(findVoice(lang));
}

function tts(text, lang) {
  return new Promise((resolve) => {
    const voice = findVoice(lang);
    if (!voice) {
      // No voice: leave time to read the text before moving on.
      const timer = setTimeout(resolve, Math.min(8000, 1500 + text.length * 60));
      endPause = () => {
        clearTimeout(timer);
        resolve();
      };
      return;
    }
    const u = new SpeechSynthesisUtterance(text);
    u.voice = voice;
    u.lang = voice.lang;
    u.volume = 1;
    u.rate = 0.95;
    u.onend = resolve;
    u.onerror = resolve;
    speechSynthesis.speak(u);
  });
}

function clip(src) {
  return new Promise((resolve, reject) => {
    const audio = new Audio(src);
    audio.volume = 1;
    current = audio;
    audio.onended = resolve;
    audio.onerror = reject;
    audio.play().catch(reject);
  });
}

// clipName is optional, e.g. 'step-3'.
export async function say(text, lang, clipName) {
  stopSpeaking();
  const src = clipName && `audio/${lang}/${clipName}.mp3`;
  if (src && !missingClips.has(src)) {
    try {
      await clip(src);
      return;
    } catch {
      missingClips.add(src);
    }
  }
  await tts(text, lang);
}

export function stopSpeaking() {
  endPause?.();
  endPause = null;
  globalThis.speechSynthesis?.cancel();
  if (current) {
    current.pause();
    current = null;
  }
}

// Voices load asynchronously in Chrome.
globalThis.speechSynthesis?.addEventListener?.('voiceschanged', () => {});
