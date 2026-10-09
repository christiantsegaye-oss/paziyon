import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seizure_alert/app_controller.dart';
import 'package:seizure_alert/core/alert_state_machine.dart';
import 'package:seizure_alert/main.dart';
import 'package:seizure_alert/core/content.dart';
import 'package:seizure_alert/models.dart';
import 'package:seizure_alert/services/services.dart';

import 'fakes.dart';

void main() {
  late DateTime now;
  late FakeVoice voice;
  late FakeSpeech speech;
  late FakeMessenger messenger;
  late MemoryStore store;
  late FakeBackground background;
  late AppController c;

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    now = DateTime(2026, 9, 25, 9);
    voice = FakeVoice();
    speech = FakeSpeech();
    messenger = FakeMessenger();
    store = MemoryStore();
    background = FakeBackground();
    c = AppController(
      AppServices(
        voice: voice,
        speech: speech,
        location: FakeLocation(),
        motion: NoMotion(),
        messenger: messenger,
        store: store,
        device: FakeDevice(),
        background: background,
      ),
      clock: () => now,
    );
    await c.load();
    await tester.pumpWidget(SeizureAlertApp(controller: c));
  }

  /// Moves the app's clock and Flutter's fake timers forward together.
  Future<void> advance(WidgetTester tester, Duration d) async {
    for (var ms = 0; ms < d.inMilliseconds; ms += 250) {
      now = now.add(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('welcome → voice trigger → echo ignored → voice cancel', (tester) async {
    await start(tester);
    expect(find.text('P.A.Z.I.Y.O.N'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(find.text('Hold for help'), findsOneWidget);
    expect(voice.listening, isTrue, reason: 'listening starts after onboarding');

    await tester.enterText(find.byKey(const Key('typeField')), 'Help me');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.machine.state, AlertState.countdown);
    expect(find.text('15'), findsOneWidget);
    expect(speech.said.last.$1, 'Alert will send in 15 seconds. Tap cancel if you are okay.');

    // The phone hearing its own prompt must not cancel the alert.
    voice.hear('tap cancel if you are okay');
    await advance(tester, const Duration(seconds: 2));
    expect(c.machine.state, AlertState.countdown);
    expect(find.text('13'), findsOneWidget);

    voice.hear("I'm okay");
    await tester.pump();
    expect(find.text('Alert cancelled'), findsOneWidget);
    expect(find.textContaining('Cancelled by voice'), findsOneWidget);
    expect(messenger.sms, isEmpty);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Hold for help'), findsOneWidget);
    expect(c.events.single.outcome, 'cancelled');
    await finish(tester);
  });

  testWidgets('hold to alert → SMS sent → bystander conversation → hold to stop', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.en);
    c.addContact(EmergencyContact(name: 'Sister', phone: '+251 911 000 000'));
    await tester.pump();

    // A quick tap does nothing; holding fires.
    await tester.tap(find.text('Hold for help'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.machine.state, AlertState.idle);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Hold for help')));
    await tester.pump(const Duration(milliseconds: 50)); // first frame starts the hold animation
    await tester.pump(const Duration(milliseconds: 900));
    await gesture.up();
    await tester.pump();
    expect(c.machine.state, AlertState.countdown);

    await advance(tester, const Duration(seconds: 16));
    expect(c.machine.state, AlertState.active);
    expect(find.text('MEDICAL EMERGENCY — PLEASE HELP'), findsOneWidget);
    expect(find.text('This person may be having a seizure. Please help them.'), findsOneWidget);

    expect(messenger.sms, hasLength(1));
    expect(messenger.sms.single.$1, ['+251911000000']);
    expect(messenger.sms.single.$2, startsWith('[EMERGENCY] Abebe Kebede may be having a seizure/fall event.'));
    expect(messenger.sms.single.$2, contains('mlat=9.0301'));
    expect(find.text('Alert SMS sent to 1 contact'), findsOneWidget);

    await advance(tester, const Duration(seconds: 4));
    await tester.enterText(find.byKey(const Key('askField')), 'How long has it been?');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.textContaining(RegExp(r'^It has been \d+ seconds\.$')), findsOneWidget);

    voice.hear('ምን ያህል ጊዜ ሆነ');
    await tester.pump();
    expect(find.textContaining('ደቂቃ'), findsOneWidget);

    voice.hear('Call for help');
    await tester.pump();
    await tester.pump();
    expect(messenger.calls, ['907']);

    await advance(tester, const Duration(seconds: 3));
    final stop = find.text('Patient returned — hold to stop alert');
    await tester.scrollUntilVisible(stop, 300, scrollable: find.byType(Scrollable).first);
    final hold = await tester.startGesture(tester.getCenter(stop));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 2100));
    await hold.up();
    await tester.pump();
    expect(find.text('Alert resolved'), findsOneWidget);
    expect(messenger.sms.last.$2, startsWith('Abebe Kebede has marked themselves as okay.'));
    expect(c.events.single.outcome, 'resolved');
    expect(c.events.single.durationSeconds, greaterThan(0));
    expect(store.data.values.single, contains('"outcome":"resolved"'));

    await tester.tap(find.text('Done'));
    await tester.pump();
    await finish(tester);
  });

  testWidgets('simulated fall runs through the detector and starts the countdown', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.om);
    await tester.pump();
    await tester.ensureVisible(find.text('Simulate a fall'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Simulate a fall'));
    await advance(tester, const Duration(seconds: 6));
    expect(c.machine.state, AlertState.countdown);
    expect(find.text('Fall detected'), findsOneWidget);
    // Prompts follow the chosen language.
    expect(speech.said.first.$2, Lang.om);
    voice.hear('Nagaan jira');
    await tester.pump();
    await tester.pump();
    expect(find.text('Alert cancelled'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('data survives a restart', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.am);
    c.addContact(EmergencyContact(name: 'Mom', phone: '0911'));
    final saved = store;
    await finish(tester);

    final c2 = AppController(
      AppServices(
        voice: FakeVoice(),
        speech: FakeSpeech(),
        location: FakeLocation(),
        motion: NoMotion(),
        messenger: FakeMessenger(),
        store: saved,
        device: FakeDevice(),
        background: FakeBackground(),
      ),
    );
    await c2.load();
    expect(c2.onboarded, isTrue);
    expect(c2.profile.name, 'አበበ ከበደ');
    expect(c2.contacts.single.name, 'Mom');
    expect(c2.settings.languageOrder.first, Lang.am);
    c2.dispose();
  });

  testWidgets('a fall the service detects while the app is on screen starts the app countdown', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.en);
    await tester.pump();
    expect(background.running, isTrue, reason: 'background protection starts after onboarding');
    expect(background.heartbeats, greaterThan(0));
    background.detectFallWhileAppOnScreen();
    await tester.pump();
    await tester.pump();
    expect(c.machine.state, AlertState.countdown);
    expect(find.text('Fall detected'), findsOneWidget);
    c.cancelAlert();
    await tester.pump();
    await finish(tester);
  });

  testWidgets('opening the app takes over an alert the service already sent, without sending again', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.en);
    c.addContact(EmergencyContact(name: 'Sister', phone: '0911'));
    await tester.pump();
    background.pending = {
      'source': 'fall',
      'triggeredAt': now.subtract(const Duration(seconds: 75)).millisecondsSinceEpoch,
      'activatedAt': now.subtract(const Duration(seconds: 60)).millisecondsSinceEpoch,
    };
    background.notificationTapped('open');
    await tester.pump();
    await tester.pump();
    expect(c.machine.state, AlertState.active);
    expect(find.text('MEDICAL EMERGENCY — PLEASE HELP'), findsOneWidget);
    expect(find.text('1:00'), findsOneWidget, reason: 'elapsed time continues from the background alert');
    expect(messenger.sms, isEmpty);
    expect(find.text('Alert SMS already sent by background protection'), findsOneWidget);
    c.resolveAlert();
    await tester.pump();
    expect(messenger.sms.single.$2, contains('has marked themselves as okay'));
    await finish(tester);
  });

  testWidgets('"I\'m okay" on the countdown notification cancels the background countdown', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.en);
    await tester.pump();
    background.pending = {'source': 'fall', 'triggeredAt': now.subtract(const Duration(seconds: 4)).millisecondsSinceEpoch};
    background.notificationTapped('cancel');
    await tester.pump();
    await tester.pump();
    expect(find.text('Alert cancelled'), findsOneWidget);
    expect(c.events.single.outcome, 'cancelled');
    expect(messenger.sms, isEmpty);
    await finish(tester);
  });

  testWidgets('voice acts on partial results even when the phone never sends a final one', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.en);
    await tester.pump();
    voice.hearPartials(['hel', 'help', 'help me'], finalResult: false);
    await tester.pump();
    await tester.pump();
    expect(c.machine.state, AlertState.countdown);
    // The rest of the same utterance must not act again (it would not cancel anyway, but must not re-trigger).
    voice.hearPartials(["I'm", "I'm okay"], finalResult: false);
    await tester.pump();
    await tester.pump();
    expect(find.text('Alert cancelled'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a bystander question is answered once, not once per partial result', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.en);
    await tester.pump();
    c.triggerManual();
    await advance(tester, const Duration(seconds: 16));
    expect(c.machine.state, AlertState.active);
    voice.hearPartials(['how', 'how long', 'how long has', 'how long has it been']);
    await tester.pump();
    await tester.pump();
    expect(c.convo.where((l) => !l.fromBystander), hasLength(1));
    voice.hearPartials(['blah', 'blah blah']);
    await tester.pump();
    expect(c.convo.where((l) => !l.fromBystander), hasLength(2), reason: 'unmatched speech answered once, on the final');
    c.resolveAlert();
    await tester.pump();
    await finish(tester);
  });

  testWidgets('why voice is not working is shown on the home screen', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.am);
    await tester.pump();
    voice.fail(VoiceStatus.error, 'Amharic speech recognition is not available on this phone, so it listens in English.');
    await tester.pump();
    expect(find.textContaining('not available on this phone'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('saying "help" works again soon after an alert, even though the phone said "help them"', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.en);
    await tester.pump();
    c.triggerManual();
    await advance(tester, const Duration(seconds: 17));
    expect(speech.said.map((s) => s.$1), contains('This person may be having a seizure. Please help them.'));
    c.resolveAlert();
    await tester.pump();
    c.finishAlert();
    await advance(tester, const Duration(seconds: 5));
    voice.hearPartials(['help'], finalResult: false);
    await tester.pump();
    await tester.pump();
    expect(c.machine.state, AlertState.countdown);
    c.cancelAlert();
    await tester.pump();
    await finish(tester);
  });

  testWidgets('"Get help now" on the lock-screen notification starts the countdown', (tester) async {
    await start(tester);
    await c.completeWelcome(Lang.en);
    await tester.pump();
    background.notificationTapped('help');
    await tester.pump();
    await tester.pump();
    expect(c.machine.state, AlertState.countdown);
    expect(find.text('Button pressed'), findsOneWidget);
    c.cancelAlert();
    await tester.pump();
    await finish(tester);
  });
}
