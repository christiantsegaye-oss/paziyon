import 'package:flutter_test/flutter_test.dart';
import 'package:seizure_alert/core/alert_state_machine.dart';
import 'package:seizure_alert/core/content.dart';
import 'package:seizure_alert/core/voice_intents.dart';

void main() {
  test('wake phrases trigger in all three languages when idle', () {
    expect(matchIntent('Help me!', AlertState.idle), const IntentMatch(Intent.trigger, Lang.en));
    expect(matchIntent('እርዳታ', AlertState.idle), const IntentMatch(Intent.trigger, Lang.am));
    expect(matchIntent('Na gargaari', AlertState.idle), const IntentMatch(Intent.trigger, Lang.om));
  });

  test('cancel phrases only work during the countdown', () {
    expect(matchIntent("I'm okay", AlertState.countdown)?.intent, Intent.cancel);
    expect(matchIntent('I’m okay', AlertState.countdown)?.intent, Intent.cancel);
    expect(matchIntent('ደህና ነኝ።', AlertState.countdown)?.intent, Intent.cancel);
    expect(matchIntent('Nagaan jira', AlertState.countdown)?.intent, Intent.cancel);
    expect(matchIntent("I'm okay", AlertState.idle), isNull);
  });

  test('bystander questions route during an active alert', () {
    expect(matchIntent('How long has it been?', AlertState.active)?.intent, Intent.elapsed);
    expect(matchIntent('What do I do now?', AlertState.active)?.intent, Intent.whatToDo);
    expect(matchIntent('Call for help', AlertState.active)?.intent, Intent.callHelp);
    expect(matchIntent("What's next", AlertState.active)?.intent, Intent.nextStep);
    expect(matchIntent('Is she on any medication?', AlertState.active)?.intent, Intent.medicalInfo);
  });

  test('answers can be given in the language the bystander used', () {
    expect(matchIntent('ምን ያህል ጊዜ ሆነ?', AlertState.active)?.lang, Lang.am);
    expect(matchIntent('Maal gochuu qaba?', AlertState.active)?.lang, Lang.om);
  });

  test('unrelated speech matches nothing', () {
    expect(matchIntent('the weather is nice', AlertState.idle), isNull);
    expect(matchIntent('the weather is nice', AlertState.active), isNull);
    expect(matchIntent('', AlertState.active), isNull);
  });

  test('the app hearing its own prompts is treated as echo', () {
    final spoken = [countdownPrompt(Lang.en, 15), firstAidSteps[Lang.en]![5]];
    expect(isEcho('tap cancel if you are okay', spoken), isTrue);
    expect(isEcho('call emergency services', spoken), isTrue);
  });

  test('a real speaker is not mistaken for echo', () {
    final spoken = [countdownPrompt(Lang.en, 15), ...firstAidSteps[Lang.en]!];
    expect(isEcho("I'm okay", spoken), isFalse);
    expect(isEcho('How long has it been?', spoken), isFalse);
    expect(isEcho('What do I do now?', spoken), isFalse);
    expect(isEcho('Call for help', spoken), isFalse);
  });

  test('elapsed answers read naturally', () {
    expect(answerElapsed(Lang.en, 1), 'It has been 1 second.');
    expect(answerElapsed(Lang.en, 125), 'It has been 2 minutes and 5 seconds.');
  });

  test('a single "help", or help inside a sentence, triggers', () {
    expect(matchIntent('Help', AlertState.idle)?.intent, Intent.trigger);
    expect(matchIntent('please help me now', AlertState.idle)?.intent, Intent.trigger);
    expect(matchIntent('ድረሱልኝ', AlertState.idle)?.lang, Lang.am);
    expect(matchIntent('Na gargaaraa', AlertState.idle)?.lang, Lang.om);
  });

  test('words that merely contain a phrase do not match', () {
    expect(matchIntent('that was helpful', AlertState.idle), isNull);
    expect(matchIntent('unstoppable', AlertState.countdown), isNull);
  });

  test('Amharic matches with attached prefixes and suffixes', () {
    expect(matchIntent('የእርዳታ ጥሪ', AlertState.idle)?.intent, Intent.trigger);
  });

  test('more natural ways to cancel', () {
    for (final phrase in ["I'm OK", 'stop', 'False alarm', "I'm alright", 'አቁም', 'Dhaabi']) {
      expect(matchIntent(phrase, AlertState.countdown)?.intent, Intent.cancel, reason: phrase);
    }
  });
}
