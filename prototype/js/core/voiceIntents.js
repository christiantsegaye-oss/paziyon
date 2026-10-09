// Maps a spoken (or typed) phrase to an intent, per alert state. This is the
// intent routing that VoiceService feeds; the speech engine behind it (Voxide
// in the real app, the browser's Web Speech API in this demo) only produces text.
//
// Amharic and Afaan Oromo phrases beyond the spec's wake/cancel phrases are
// drafts that need native-speaker review.

import { STATES } from './alertStateMachine.js';

export const INTENTS = Object.freeze({
  TRIGGER: 'trigger',
  CANCEL: 'cancel',
  ELAPSED: 'elapsed',
  WHAT_TO_DO: 'what_to_do',
  NEXT_STEP: 'next_step',
  REPEAT: 'repeat',
  CALL_HELP: 'call_help',
  MEDICAL_INFO: 'medical_info',
});

const PHRASES = {
  [INTENTS.TRIGGER]: {
    en: ['help', 'emergency', 'ambulance'],
    am: ['እርዳታ', 'እርዱኝ', 'እርዳኝ', 'ድረሱልኝ', 'ድረሱ'],
    om: ['gargaari', 'gargaaraa', 'gargaarsa'],
  },
  [INTENTS.CANCEL]: {
    en: [
      "i'm okay", 'i am okay', 'im okay', "i'm ok", 'i am ok', 'im ok', "i'm fine", 'i am fine', "i'm alright",
      "i'm all right", "i'm good", 'false alarm', 'cancel', 'stop',
    ],
    am: ['ደህና ነኝ', 'ሰርዝ', 'አቁም'],
    om: ['nagaan jira', 'nagaa dha', 'haqi', 'dhaabi'],
  },
  [INTENTS.ELAPSED]: {
    en: ['how long', 'how much time', 'what time', 'how many minutes'],
    am: ['ምን ያህል ጊዜ', 'ስንት ደቂቃ', 'ምን ያህል ሆነ'],
    om: ['hammam ture', 'yeroo hammam', 'daqiiqaa meeqa'],
  },
  [INTENTS.CALL_HELP]: {
    en: ['call for help', 'call help', 'call an ambulance', 'call ambulance', 'call emergency', 'call 907'],
    am: ['አምቡላንስ', 'ደውል', 'ጥራ'],
    om: ['ambulaansii', 'bilbili', 'gargaarsa bilbili'],
  },
  [INTENTS.NEXT_STEP]: {
    en: ['next', 'then what', 'what else'],
    am: ['ቀጥሎ', 'ከዚያስ'],
    om: ['itti aanu', 'kana booda'],
  },
  [INTENTS.REPEAT]: {
    en: ['repeat', 'say again', 'say that again', 'pardon'],
    am: ['ድገም', 'ይድገሙ', 'እንደገና'],
    om: ['irra deebi', 'deebisi'],
  },
  [INTENTS.WHAT_TO_DO]: {
    en: ['what do i do', 'what should i do', 'what now', 'what do i need to do', 'how do i help', 'what can i do'],
    am: ['ምን ላድርግ', 'ምን ማድረግ አለብኝ', 'እንዴት ልርዳ'],
    om: ['maal gochuu qaba', 'maal haa godhu', 'akkamittan gargaaru'],
  },
  [INTENTS.MEDICAL_INFO]: {
    en: ['medication', 'medications', 'medicine', 'allergy', 'allergies', 'allergic', 'who is', 'their name', 'condition'],
    am: ['መድሃኒት', 'መድኃኒት', 'አለርጂ', 'ማን ነው'],
    om: ['qoricha', 'alarjii', 'eenyu'],
  },
};

// Which intents are listened for in each alert state. Earlier entries win when
// a phrase matches more than one intent.
const INTENTS_BY_STATE = {
  [STATES.IDLE]: [INTENTS.TRIGGER],
  [STATES.COUNTDOWN]: [INTENTS.CANCEL],
  [STATES.ACTIVE]: [
    INTENTS.ELAPSED,
    INTENTS.CALL_HELP,
    INTENTS.NEXT_STEP,
    INTENTS.REPEAT,
    INTENTS.WHAT_TO_DO,
    INTENTS.MEDICAL_INFO,
    INTENTS.CANCEL,
  ],
  [STATES.RESOLVED]: [],
};

export function normalize(text) {
  return text
    .toLowerCase()
    .replace(/[’`]/g, "'")
    .replace(/[.,!?;:"“”።፣፤፥፦]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// Returns { intent, lang } or null. lang is the language the phrase matched in,
// so answers can be spoken back in the bystander's language.
// Latin-script phrases match whole words only ("help" but not "helpful").
// Ge'ez phrases match anywhere, because Amharic attaches prefixes and
// suffixes to words (የእርዳታ, እርዳታዬ).
function contains(said, phrase) {
  const p = normalize(phrase);
  return /[a-z]/.test(p) ? ` ${said} `.includes(` ${p} `) : said.includes(p);
}

export function matchIntent(text, state) {
  const said = normalize(text);
  if (!said) return null;
  for (const intent of INTENTS_BY_STATE[state] ?? []) {
    for (const [lang, phrases] of Object.entries(PHRASES[intent])) {
      if (phrases.some((p) => contains(said, p))) return { intent, lang };
    }
  }
  return null;
}

// The microphone hears the phone's own speech. A transcript is treated as an
// echo when most of its words were in something the app said recently, so the
// countdown prompt ("Tap cancel if you are okay") cannot cancel itself and the
// first-aid step "call emergency services" cannot dial.
export function isEcho(transcript, recentlySpoken, threshold = 0.75) {
  const words = normalize(transcript).split(' ').filter(Boolean);
  if (!words.length) return false;
  const spoken = new Set(recentlySpoken.flatMap((t) => normalize(t).split(' ')));
  const overlap = words.filter((w) => spoken.has(w)).length / words.length;
  return overlap >= threshold;
}
