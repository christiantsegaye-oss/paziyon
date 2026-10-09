// Emergency content in the three target languages. Port of
// prototype/js/core/content.js.
//
// English follows the spec (section 4.3). The Amharic and Afaan Oromo text is a
// DRAFT: it must be reviewed by native speakers and by Care Epilepsy Ethiopia
// before any real use, and it will be replaced by the clinically reviewed
// recordings.

enum Lang { am, om, en }

extension LangInfo on Lang {
  String get label => const {Lang.am: 'አማርኛ', Lang.om: 'Afaan Oromoo', Lang.en: 'English'}[this]!;
  String get short => const {Lang.am: 'AM', Lang.om: 'OR', Lang.en: 'EN'}[this]!;

  /// BCP-47 tag used for speech recognition and synthesis.
  String get tag => const {Lang.am: 'am-ET', Lang.om: 'om-ET', Lang.en: 'en-US'}[this]!;
}

const emergencyHeader = {
  Lang.am: 'የሕክምና ድንገተኛ — እባክዎ ይርዱ',
  Lang.om: 'Balaa Fayyaa Tasaa — Maaloo Gargaaraa',
  Lang.en: 'MEDICAL EMERGENCY — PLEASE HELP',
};

const firstAidSteps = {
  Lang.en: [
    'This person may be having a seizure. Please help them.',
    'Do NOT restrain them. Do NOT put anything in their mouth.',
    'Clear the area around them of hard or sharp objects.',
    'If possible, gently ease them onto their side.',
    'Cushion their head with something soft.',
    'Time the seizure. If it lasts more than 5 minutes, call emergency services.',
    'Stay with them until they are fully conscious.',
  ],
  Lang.am: [
    'ይህ ሰው የሚጥል ሕመም እያጋጠመው ሊሆን ይችላል። እባክዎ ይርዱት።',
    'አይያዙት ወይም አያስሩት። በአፉ ውስጥ ምንም ነገር አያስገቡ።',
    'በዙሪያው ያሉ ጠንካራ ወይም ስለታም ነገሮችን ያርቁ።',
    'ከተቻለ በቀስታ በጎኑ ያስተኙት።',
    'ከራሱ ስር ለስላሳ ነገር ያድርጉ።',
    'ጊዜውን ይቁጠሩ። ከ5 ደቂቃ በላይ ከቆየ የአደጋ ጊዜ አገልግሎት ይደውሉ።',
    'ሙሉ በሙሉ እስኪነቃ ድረስ አብረውት ይቆዩ።',
  ],
  Lang.om: [
    "Namni kun dhukkuba kufaatii qabachuu danda'a. Maaloo isa gargaaraa.",
    'Isa hin qabinaa, hin hidhinaa. Afaan isaa keessa homaa hin galchinaa.',
    'Naannoo isaa irraa meeshaalee jajjaboo fi qara qaban fageessaa.',
    "Yoo danda'ame, suuta cinaacha isaatti isa ciisisaa.",
    "Mataa isaa jala waan laafaa kaa'aa.",
    "Yeroo lakkaa'aa. Yoo daqiiqaa 5 ol ture, tajaajila balaa tasaa bilbilaa.",
    'Hanga guutummaatti dammaqutti isa bira turaa.',
  ],
};

String countdownPrompt(Lang lang, int n) => switch (lang) {
      Lang.en => 'Alert will send in $n seconds. Tap cancel if you are okay.',
      Lang.am => 'ማስጠንቀቂያው በ$n ሰከንድ ውስጥ ይላካል። ደህና ከሆኑ ሰርዝን ይጫኑ።',
      Lang.om => 'Akeekkachiisni sekondii $n keessatti ni ergama. Yoo nagaa taatan haquu tuqaa.',
    };

String answerElapsed(Lang lang, int seconds) {
  final m = seconds ~/ 60, s = seconds % 60;
  return switch (lang) {
    Lang.en => 'It has been ${m > 0 ? '$m minute${m == 1 ? '' : 's'} and ' : ''}$s second${s == 1 ? '' : 's'}.',
    Lang.am => '$m ደቂቃ ከ$s ሰከንድ ሆኗል።',
    Lang.om => "Daqiiqaa $m fi sekondii $s ta'eera.",
  };
}

const answerOverFiveMinutes = {
  Lang.en: 'That is more than 5 minutes. Call emergency services now.',
  Lang.am: 'ከ5 ደቂቃ በላይ ሆኗል። አሁኑኑ የአደጋ ጊዜ አገልግሎት ይደውሉ።',
  Lang.om: "Daqiiqaa 5 ol ta'eera. Amma tajaajila balaa tasaa bilbilaa.",
};

const answerCalling = {
  Lang.en: 'Calling emergency services.',
  Lang.am: 'ወደ አደጋ ጊዜ አገልግሎት እየደወልኩ ነው።',
  Lang.om: 'Tajaajila balaa tasaatti bilbilaa jira.',
};

const answerHoldToStop = {
  Lang.en: 'To stop the alert, hold the Patient returned button.',
  Lang.am: 'ማስጠንቀቂያውን ለማቆም "ታካሚው ተመልሷል" የሚለውን ቁልፍ ተጭነው ይያዙ።',
  Lang.om: "Akeekkachiisa dhaabuuf, qabduu \"Dhukkubsataan deebi'eera\" qabadhaa.",
};

const answerNotUnderstood = {
  Lang.en: 'Ask: how long has it been, what do I do now, next step, or call for help.',
  Lang.am: 'ይጠይቁ፦ ምን ያህል ጊዜ ሆነ፣ ምን ላድርግ፣ ቀጥሎ፣ ወይም አምቡላንስ ጥራ።',
  Lang.om: 'Gaafadhaa: hammam ture, maal gochuu qaba, itti aanu, ykn gargaarsa bilbili.',
};

String answerMedical(Lang lang, {String? name, String? condition, String? medications, String? allergies}) {
  String or(String? v, String fallback) => (v == null || v.isEmpty) ? fallback : v;
  return switch (lang) {
    Lang.en => 'Their name is ${or(name, 'unknown')}. Condition: ${or(condition, 'unknown')}. '
        'Medications: ${or(medications, 'none listed')}. Allergies: ${or(allergies, 'none listed')}.',
    Lang.am => 'ስማቸው ${or(name, 'አይታወቅም')} ነው። ሕመም፦ ${or(condition, 'አይታወቅም')}። '
        'መድሃኒት፦ ${or(medications, 'አልተመዘገበም')}። አለርጂ፦ ${or(allergies, 'አልተመዘገበም')}።',
    Lang.om => 'Maqaan isaanii ${or(name, 'hin beekamu')}. Dhukkuba: ${or(condition, 'hin beekamu')}. '
        'Qoricha: ${or(medications, 'hin galmoofne')}. Alarjii: ${or(allergies, 'hin galmoofne')}.',
  };
}

/// Spoken elapsed time in whole minutes. The exact time is on screen; spoken
/// answers use pre-recorded clips (`assets/audio/<lang>/elapsed-<m>.mp3`), so
/// they are rounded to minutes. Mirrors ELAPSED_SPOKEN in content.js, which the
/// clip generator reads.
String elapsedSpoken(Lang lang, int m) => switch (lang) {
      Lang.en => m == 0 ? 'Less than a minute.' : '$m minute${m == 1 ? '' : 's'}.',
      Lang.am => m == 0 ? 'ገና አንድ ደቂቃ አልሞላም።' : '$m ደቂቃ ሆኗል።',
      Lang.om => m == 0 ? 'Daqiiqaa tokko hin guunne.' : "Daqiiqaa $m ta'eera.",
    };

/// Ethiopian emergency numbers: 907 ambulance (Red Cross), 991 police, 939 fire.
const emergencyNumber = '907';
