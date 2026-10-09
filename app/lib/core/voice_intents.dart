// Maps a spoken (or typed) phrase to an intent, per alert state. This is the
// intent routing VoiceService feeds; the speech engine behind it only produces
// text. Port of prototype/js/core/voiceIntents.js.
//
// Amharic and Afaan Oromo phrases beyond the spec's wake/cancel phrases are
// drafts that need native-speaker review.

import 'alert_state_machine.dart';
import 'content.dart';

enum Intent { trigger, cancel, elapsed, whatToDo, nextStep, repeat, callHelp, medicalInfo }

class IntentMatch {
  const IntentMatch(this.intent, this.lang);
  final Intent intent;

  /// The language the phrase matched in, so answers can be given in it.
  final Lang lang;

  @override
  bool operator ==(Object other) => other is IntentMatch && other.intent == intent && other.lang == lang;

  @override
  int get hashCode => Object.hash(intent, lang);

  @override
  String toString() => 'IntentMatch($intent, $lang)';
}

const _phrases = <Intent, Map<Lang, List<String>>>{
  Intent.trigger: {
    Lang.en: ['help', 'emergency', 'ambulance'],
    Lang.am: ['እርዳታ', 'እርዱኝ', 'እርዳኝ', 'ድረሱልኝ', 'ድረሱ'],
    Lang.om: ['gargaari', 'gargaaraa', 'gargaarsa'],
  },
  Intent.cancel: {
    Lang.en: [
      "i'm okay", 'i am okay', 'im okay', "i'm ok", 'i am ok', 'im ok', "i'm fine", 'i am fine', "i'm alright",
      "i'm all right", "i'm good", 'false alarm', 'cancel', 'stop',
    ],
    Lang.am: ['ደህና ነኝ', 'ሰርዝ', 'አቁም'],
    Lang.om: ['nagaan jira', 'nagaa dha', 'haqi', 'dhaabi'],
  },
  Intent.elapsed: {
    Lang.en: ['how long', 'how much time', 'what time', 'how many minutes'],
    Lang.am: ['ምን ያህል ጊዜ', 'ስንት ደቂቃ', 'ምን ያህል ሆነ'],
    Lang.om: ['hammam ture', 'yeroo hammam', 'daqiiqaa meeqa'],
  },
  Intent.callHelp: {
    Lang.en: ['call for help', 'call help', 'call an ambulance', 'call ambulance', 'call emergency', 'call 907'],
    Lang.am: ['አምቡላንስ', 'ደውል', 'ጥራ'],
    Lang.om: ['ambulaansii', 'bilbili', 'gargaarsa bilbili'],
  },
  Intent.nextStep: {
    Lang.en: ['next', 'then what', 'what else'],
    Lang.am: ['ቀጥሎ', 'ከዚያስ'],
    Lang.om: ['itti aanu', 'kana booda'],
  },
  Intent.repeat: {
    Lang.en: ['repeat', 'say again', 'say that again', 'pardon'],
    Lang.am: ['ድገም', 'ይድገሙ', 'እንደገና'],
    Lang.om: ['irra deebi', 'deebisi'],
  },
  Intent.whatToDo: {
    Lang.en: ['what do i do', 'what should i do', 'what now', 'what do i need to do', 'how do i help', 'what can i do'],
    Lang.am: ['ምን ላድርግ', 'ምን ማድረግ አለብኝ', 'እንዴት ልርዳ'],
    Lang.om: ['maal gochuu qaba', 'maal haa godhu', 'akkamittan gargaaru'],
  },
  Intent.medicalInfo: {
    Lang.en: ['medication', 'medications', 'medicine', 'allergy', 'allergies', 'allergic', 'who is', 'their name', 'condition'],
    Lang.am: ['መድሃኒት', 'መድኃኒት', 'አለርጂ', 'ማን ነው'],
    Lang.om: ['qoricha', 'alarjii', 'eenyu'],
  },
};

// Which intents are listened for in each alert state. Earlier entries win when
// a phrase matches more than one intent.
const _intentsByState = <AlertState, List<Intent>>{
  AlertState.idle: [Intent.trigger],
  AlertState.countdown: [Intent.cancel],
  AlertState.active: [
    Intent.elapsed,
    Intent.callHelp,
    Intent.nextStep,
    Intent.repeat,
    Intent.whatToDo,
    Intent.medicalInfo,
    Intent.cancel,
  ],
  AlertState.resolved: [],
};

final _quotes = RegExp('[’`]');
final _punctuation = RegExp(r'[.,!?;:"“”።፣፤፥፦]');
final _spaces = RegExp(r'\s+');

String normalize(String text) => text
    .toLowerCase()
    .replaceAll(_quotes, "'")
    .replaceAll(_punctuation, ' ')
    .replaceAll(_spaces, ' ')
    .trim();

final _latin = RegExp('[a-z]');

/// Latin-script phrases match whole words only ("help" but not "helpful").
/// Ge'ez phrases match anywhere, because Amharic attaches prefixes and
/// suffixes to words (የእርዳታ, እርዳታዬ).
bool _contains(String said, String phrase) {
  final p = normalize(phrase);
  return _latin.hasMatch(p) ? ' $said '.contains(' $p ') : said.contains(p);
}

IntentMatch? matchIntent(String text, AlertState state) {
  final said = normalize(text);
  if (said.isEmpty) return null;
  for (final intent in _intentsByState[state]!) {
    for (final MapEntry(key: lang, value: phrases) in _phrases[intent]!.entries) {
      if (phrases.any((p) => _contains(said, p))) return IntentMatch(intent, lang);
    }
  }
  return null;
}

/// The microphone hears the phone's own speech. A transcript is treated as an
/// echo when most of its words were in something the app said recently, so the
/// countdown prompt ("Tap cancel if you are okay") cannot cancel itself and the
/// first-aid step "call emergency services" cannot dial.
bool isEcho(String transcript, Iterable<String> recentlySpoken, {double threshold = 0.75}) {
  final words = normalize(transcript).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return false;
  final spoken = recentlySpoken.expand((t) => normalize(t).split(' ')).toSet();
  final overlap = words.where(spoken.contains).length / words.length;
  return overlap >= threshold;
}
