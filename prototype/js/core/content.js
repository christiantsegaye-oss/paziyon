// Emergency content in the three target languages.
//
// English follows the spec (section 4.3). The Amharic and Afaan Oromo text is a
// DRAFT for the demo only: it must be reviewed by native speakers and by Care
// Epilepsy Ethiopia before any real use, and it will be replaced by the
// clinically reviewed recordings.

export const LANGS = ['am', 'om', 'en'];

export const LANG_LABELS = { am: 'አማርኛ', om: 'Afaan Oromoo', en: 'English' };
export const LANG_SHORT = { am: 'AM', om: 'OR', en: 'EN' };
// BCP-47 tags used for speech recognition and synthesis.
export const LANG_TAGS = { am: 'am-ET', om: 'om-ET', en: 'en-US' };

export const EMERGENCY_HEADER = {
  am: 'የሕክምና ድንገተኛ — እባክዎ ይርዱ',
  om: 'Balaa Fayyaa Tasaa — Maaloo Gargaaraa',
  en: 'MEDICAL EMERGENCY — PLEASE HELP',
};

export const FIRST_AID_STEPS = {
  en: [
    'This person may be having a seizure. Please help them.',
    'Do NOT restrain them. Do NOT put anything in their mouth.',
    'Clear the area around them of hard or sharp objects.',
    'If possible, gently ease them onto their side.',
    'Cushion their head with something soft.',
    'Time the seizure. If it lasts more than 5 minutes, call emergency services.',
    'Stay with them until they are fully conscious.',
  ],
  am: [
    'ይህ ሰው የሚጥል ሕመም እያጋጠመው ሊሆን ይችላል። እባክዎ ይርዱት።',
    'አይያዙት ወይም አያስሩት። በአፉ ውስጥ ምንም ነገር አያስገቡ።',
    'በዙሪያው ያሉ ጠንካራ ወይም ስለታም ነገሮችን ያርቁ።',
    'ከተቻለ በቀስታ በጎኑ ያስተኙት።',
    'ከራሱ ስር ለስላሳ ነገር ያድርጉ።',
    'ጊዜውን ይቁጠሩ። ከ5 ደቂቃ በላይ ከቆየ የአደጋ ጊዜ አገልግሎት ይደውሉ።',
    'ሙሉ በሙሉ እስኪነቃ ድረስ አብረውት ይቆዩ።',
  ],
  om: [
    "Namni kun dhukkuba kufaatii qabachuu danda'a. Maaloo isa gargaaraa.",
    'Isa hin qabinaa, hin hidhinaa. Afaan isaa keessa homaa hin galchinaa.',
    'Naannoo isaa irraa meeshaalee jajjaboo fi qara qaban fageessaa.',
    "Yoo danda'ame, suuta cinaacha isaatti isa ciisisaa.",
    'Mataa isaa jala waan laafaa kaa\'aa.',
    'Yeroo lakkaa\'aa. Yoo daqiiqaa 5 ol ture, tajaajila balaa tasaa bilbilaa.',
    'Hanga guutummaatti dammaqutti isa bira turaa.',
  ],
};

export const COUNTDOWN_PROMPT = {
  en: (n) => `Alert will send in ${n} seconds. Tap cancel if you are okay.`,
  am: (n) => `ማስጠንቀቂያው በ${n} ሰከንድ ውስጥ ይላካል። ደህና ከሆኑ ሰርዝን ይጫኑ።`,
  om: (n) => `Akeekkachiisni sekondii ${n} keessatti ni ergama. Yoo nagaa taatan haquu tuqaa.`,
};

// Spoken answers for the bystander conversation.
export const ANSWERS = {
  elapsed: {
    en: (m, s) =>
      `It has been ${m ? `${m} minute${m === 1 ? '' : 's'} and ` : ''}${s} second${s === 1 ? '' : 's'}.`,
    am: (m, s) => `${m} ደቂቃ ከ${s} ሰከንድ ሆኗል።`,
    om: (m, s) => `Daqiiqaa ${m} fi sekondii ${s} ta'eera.`,
  },
  overFiveMinutes: {
    en: 'That is more than 5 minutes. Call emergency services now.',
    am: 'ከ5 ደቂቃ በላይ ሆኗል። አሁኑኑ የአደጋ ጊዜ አገልግሎት ይደውሉ።',
    om: 'Daqiiqaa 5 ol ta\'eera. Amma tajaajila balaa tasaa bilbilaa.',
  },
  calling: {
    en: 'Calling emergency services.',
    am: 'ወደ አደጋ ጊዜ አገልግሎት እየደወልኩ ነው።',
    om: 'Tajaajila balaa tasaatti bilbilaa jira.',
  },
  holdToStop: {
    en: 'To stop the alert, hold the Patient returned button.',
    am: 'ማስጠንቀቂያውን ለማቆም "ታካሚው ተመልሷል" የሚለውን ቁልፍ ተጭነው ይያዙ።',
    om: 'Akeekkachiisa dhaabuuf, qabduu "Dhukkubsataan deebi\'eera" qabadhaa.',
  },
  notUnderstood: {
    en: 'Ask: how long has it been, what do I do now, next step, or call for help.',
    am: 'ይጠይቁ፦ ምን ያህል ጊዜ ሆነ፣ ምን ላድርግ፣ ቀጥሎ፣ ወይም አምቡላንስ ጥራ።',
    om: 'Gaafadhaa: hammam ture, maal gochuu qaba, itti aanu, ykn gargaarsa bilbili.',
  },
  medical: {
    en: (p) => `Their name is ${p.name || 'unknown'}. Condition: ${p.condition || 'unknown'}. Medications: ${p.medications || 'none listed'}. Allergies: ${p.allergies || 'none listed'}.`,
    am: (p) => `ስማቸው ${p.name || 'አይታወቅም'} ነው። ሕመም፦ ${p.condition || 'አይታወቅም'}። መድሃኒት፦ ${p.medications || 'አልተመዘገበም'}። አለርጂ፦ ${p.allergies || 'አልተመዘገበም'}።`,
    om: (p) => `Maqaan isaanii ${p.name || 'hin beekamu'}. Dhukkuba: ${p.condition || 'hin beekamu'}. Qoricha: ${p.medications || 'hin galmoofne'}. Alarjii: ${p.allergies || 'hin galmoofne'}.`,
  },
};

// Spoken elapsed time in whole minutes. The exact time is on screen; spoken
// answers use pre-recorded clips (audio/<lang>/elapsed-<m>.mp3), so they're
// rounded to minutes.
export const ELAPSED_SPOKEN = {
  en: (m) => (m === 0 ? 'Less than a minute.' : `${m} minute${m === 1 ? '' : 's'}.`),
  am: (m) => (m === 0 ? 'ገና አንድ ደቂቃ አልሞላም።' : `${m} ደቂቃ ሆኗል።`),
  om: (m) => (m === 0 ? 'Daqiiqaa tokko hin guunne.' : `Daqiiqaa ${m} ta'eera.`),
};

// Ethiopian emergency numbers: 907 ambulance (Red Cross), 991 police, 939 fire.
export const EMERGENCY_NUMBER = '907';
