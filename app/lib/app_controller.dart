import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleListener, ChangeNotifier;

import 'core/alert_message.dart';
import 'core/alert_state_machine.dart';
import 'core/background_coordinator.dart';
import 'core/content.dart';
import 'core/fall_detector.dart';
import 'core/voice_intents.dart';
import 'models.dart';
import 'services/services.dart';


class ConvoLine {
  const ConvoLine(this.fromBystander, this.text);
  final bool fromBystander;
  final String text;
}

/// Owns the alert state machine, fall detector, voice pipeline and bystander
/// loop, and everything the screens show. The UI only reads this and calls
/// its methods.
class AppController extends ChangeNotifier {
  AppController(this.services, {Clock? clock}) : _clock = clock ?? DateTime.now {
    machine = AlertStateMachine(clock: _clock);
    machine.subscribe(_onAlert);
    detector = FallDetector(
      onStage: (s) {
        fallStage = s;
        notifyListeners();
      },
      onFall: (_) => machine.trigger(TriggerSource.fall),
    );
  }

  final AppServices services;
  final Clock _clock;
  late final AlertStateMachine machine;
  late final FallDetector detector;

  // Stored data
  UserProfile profile = UserProfile();
  List<EmergencyContact> contacts = [];
  AppSettings settings = AppSettings();
  List<EventLog> events = [];
  bool loaded = false;
  bool onboarded = false;

  // Live state
  AlertSnapshot alert = const AlertSnapshot(state: AlertState.idle, event: AlertEvent.reset);
  VoiceStatus voiceStatus = VoiceStatus.off;
  Lang listenLang = Lang.en;
  String? lastHeard;

  /// Why voice is not working, or which language it really listens in.
  String? voiceDetail;

  /// What the microphone is hearing right now (partial results included), so
  /// people can see voice working.
  String? hearing;
  FallStage fallStage = FallStage.monitor;
  bool motionAvailable = true;
  bool simulatingFall = false;

  // Bystander mode
  int step = 0;
  Lang stepLang = Lang.en;
  bool cycleLanguages = true;
  final convo = <ConvoLine>[];
  String? smsStatus;
  AlertDetails? _details;
  EventLog? _event;

  /// The alert was sent by the background service before the app took over.
  bool _smsSentInBackground = false;
  Timer? _heartbeat;
  AppLifecycleListener? _lifecycle;

  int _loopGen = 0;
  Timer? _ticker;
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<MotionSample>? _motionSub;

  // ------------------------------------------------------------------ lifecycle

  Future<void> load() async {
    final raw = await services.store.read(storeKey);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        profile = UserProfile.fromJson(j['profile'] as Map<String, dynamic>? ?? {});
        contacts = [
          for (final c in j['contacts'] as List? ?? []) EmergencyContact.fromJson(c as Map<String, dynamic>),
        ];
        settings = AppSettings.fromJson(j['settings'] as Map<String, dynamic>? ?? {});
        events = [for (final e in j['events'] as List? ?? []) EventLog.fromJson(e as Map<String, dynamic>)];
      } catch (_) {
        // Corrupt data: start fresh rather than crash an emergency app.
      }
    }
    onboarded = profile.name.isNotEmpty;
    listenLang = settings.language;
    machine.cancelWindowSeconds = settings.cancelWindowSeconds;
    detector.sensitivity = settings.sensitivity;

    _subs.add(services.voice.heard.listen(_onHeard));
    _subs.add(services.voice.status.listen((s) {
      voiceStatus = s;
      voiceDetail = services.voice.detail;
      notifyListeners();
    }));
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => machine.tick());
    unawaited(services.location.start());
    _applyFallDetection();

    final bg = services.background;
    _subs.add(bg.forwardedFalls.listen((_) => machine.trigger(TriggerSource.fall)));
    _subs.add(bg.notificationActions.listen((a) async {
      await takeOverBackgroundAlert(cancel: a == 'cancel');
      // "Get help now" on the lock-screen notification.
      if (a == 'help' && machine.state == AlertState.idle) machine.trigger(TriggerSource.manual);
    }));
    _lifecycle = AppLifecycleListener(onResume: _onShown, onPause: _onHidden);
    _onShown();
    if (onboarded) unawaited(_applyBackgroundProtection());

    loaded = true;
    notifyListeners();
    if (onboarded && settings.voiceTrigger) unawaited(startListening());
  }

  // While the app is on screen the service hands falls to it; once hidden, the
  // service handles them itself (see BackgroundCoordinator).
  void _onShown() {
    services.background.heartbeat();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) => services.background.heartbeat());
    unawaited(takeOverBackgroundAlert());
  }

  void _onHidden() {
    _heartbeat?.cancel();
    services.background.hidden();
  }

  Future<void> _applyBackgroundProtection() =>
      settings.backgroundProtection ? services.background.start() : services.background.stop();

  /// Continues a countdown or alert the background service started, with its
  /// original timing. [cancel] is the notification's "I'm okay" action.
  Future<void> takeOverBackgroundAlert({bool cancel = false}) async {
    if (machine.state == AlertState.idle) {
      final handed = parseHandOver(await services.background.takeOver());
      await _mergeStoredEvents();
      if (handed != null && machine.state == AlertState.idle) {
        _smsSentInBackground = handed.activatedAt != null;
        machine.restore(source: handed.source, triggeredAt: handed.triggeredAt, activatedAt: handed.activatedAt);
      }
    }
    if (cancel) machine.cancel('tap');
  }

  /// Picks up events the background service logged while the app was closed.
  Future<void> _mergeStoredEvents() async {
    final raw = await services.store.read(storeKey);
    if (raw == null) return;
    try {
      final stored = (jsonDecode(raw) as Map<String, dynamic>)['events'] as List? ?? [];
      final known = {for (final e in events) e.id};
      final added = [
        for (final e in stored)
          if (!known.contains((e as Map<String, dynamic>)['id'])) EventLog.fromJson(e),
      ];
      if (added.isEmpty) return;
      events = [...events, ...added]..sort((a, b) => b.time.compareTo(a.time));
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _heartbeat?.cancel();
    _lifecycle?.dispose();
    _motionSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _save() => services.store.write(
        storeKey,
        jsonEncode({
          'profile': profile.toJson(),
          'contacts': contacts.map((c) => c.toJson()).toList(),
          'settings': settings.toJson(),
          'events': events.map((e) => e.toJson()).toList(),
        }),
      );

  Future<void> completeWelcome(Lang lang) async {
    loadDemoProfile(lang);
    onboarded = true;
    notifyListeners();
    unawaited(_applyBackgroundProtection());
    await startListening();
  }

  void loadDemoProfile(Lang lang) {
    profile = UserProfile.demo(lang);
    settings.language = lang;
    // Start the instruction loop in the chosen language.
    settings.languageOrder = [lang, ...Lang.values.where((l) => l != lang)];
    listenLang = lang;
    _save();
    notifyListeners();
  }

  Future<void> deleteAll() async {
    await services.store.delete(storeKey);
    profile = UserProfile();
    contacts = [];
    settings = AppSettings();
    events = [];
    onboarded = false;
    notifyListeners();
  }

  // ------------------------------------------------------------------ voice

  Future<void> startListening() => services.voice.start(listenLang);
  Future<void> stopListening() => services.voice.stop();

  Future<void> setListenLang(Lang lang) async {
    listenLang = lang;
    notifyListeners();
    if (services.voice.listening) await services.voice.start(lang);
  }

  /// What the phone said, so the microphone can ignore its own voice. Only
  /// speech still playing or ended in the last few seconds counts; otherwise a
  /// first-aid step like "Please help them" would block a real "help" long
  /// after the alert.
  static const _echoWindow = Duration(seconds: 4);
  final _spoken = <({String text, DateTime? until})>[];

  List<String> get _recentlySpoken {
    final now = _clock();
    return [for (final e in _spoken) if (e.until == null || e.until!.isAfter(now)) e.text];
  }

  Future<void> _speak(String text, Lang lang, {String? clip}) async {
    final entry = (text: text, until: null as DateTime?);
    _spoken.add(entry);
    if (_spoken.length > 8) _spoken.removeAt(0);
    try {
      await services.speech.say(text, lang, clip: clip);
    } finally {
      final i = _spoken.indexOf(entry);
      if (i >= 0) _spoken[i] = (text: text, until: _clock().add(_echoWindow));
    }
  }

  int? _actedOnUtterance;

  /// Speech acts on the first partial result that matches, so "help" works
  /// the moment it is said, and once per utterance, so a question is never
  /// answered twice.
  void _onHeard(Heard h) {
    if (h.utterance == _actedOnUtterance) return;
    if (isEcho(h.text, _recentlySpoken)) return;
    hearing = h.text;
    notifyListeners();
    if (_route(h.text, isFinal: h.isFinal)) _actedOnUtterance = h.utterance;
  }

  /// Typed text goes through the same routing as speech.
  void handleTranscript(String text) => _route(text, isFinal: true);

  /// Returns whether the text was acted on.
  bool _route(String text, {required bool isFinal}) {
    final match = matchIntent(text, machine.state);
    switch (machine.state) {
      case AlertState.idle:
        lastHeard = text;
        notifyListeners();
        if (match?.intent == Intent.trigger && settings.voiceTrigger) {
          machine.trigger(TriggerSource.voice);
          return true;
        }
        return false;
      case AlertState.countdown:
        if (match?.intent == Intent.cancel) {
          machine.cancel('voice');
          return true;
        }
        return false;
      case AlertState.active:
        // Wait for the question to finish unless it already matches.
        if (match == null && !isFinal) return false;
        convo.insert(0, ConvoLine(true, text));
        notifyListeners();
        _answerBystander(match);
        return true;
      case AlertState.resolved:
        return false;
    }
  }

  // ------------------------------------------------------------------ triggers

  void triggerManual() => machine.trigger(TriggerSource.manual);
  void cancelAlert() => machine.cancel('tap');
  void resolveAlert() => machine.resolve('tap');
  void finishAlert() => machine.reset();

  void _applyFallDetection() {
    _motionSub?.cancel();
    _motionSub = null;
    if (!settings.fallDetection) return;
    final stream = services.motion.samples();
    motionAvailable = stream != null;
    // Real readings pause while a simulated fall plays through the detector.
    _motionSub = stream?.listen((s) {
      if (!simulatingFall) _feedDetector(s);
    }, onError: (_) {
      motionAvailable = false;
      notifyListeners();
    });
  }

  void _feedDetector(MotionSample s) {
    if (settings.fallDetection && machine.state == AlertState.idle) detector.push(s);
  }

  /// Plays freefall → impact → stillness through the real detector, for demos.
  Future<void> simulateFall() async {
    if (!settings.fallDetection || simulatingFall) return;
    simulatingFall = true;
    detector.reset();
    notifyListeners();
    final segments = <(int, double)>[(500, 9.8), (350, 0.8), (60, 34), (250, 17), (3600, 9.8)];
    var t = 0;
    for (final (ms, mag) in segments) {
      for (var e = 0; e < ms; e += 20, t += 20) {
        _feedDetector(MotionSample(t, 0, 0, mag));
        if (t % 200 == 0) await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    simulatingFall = false;
    notifyListeners();
  }

  // ------------------------------------------------------------------ alert lifecycle

  void _onAlert(AlertSnapshot snap) {
    alert = snap;
    switch (snap.event) {
      case AlertEvent.triggered:
        _onTriggered(snap);
      case AlertEvent.countdown:
        _onCountdown(snap);
      case AlertEvent.activated:
        _onActivated(snap);
      case AlertEvent.cancelled:
      case AlertEvent.resolved:
        _onFinished(snap);
      case AlertEvent.reset:
        detector.reset();
        convo.clear();
        smsStatus = null;
        _details = null;
        _event = null;
      case AlertEvent.tick:
        break;
    }
    notifyListeners();
  }

  void _onTriggered(AlertSnapshot snap) {
    services.device.keepScreenOn(true);
    final loc = services.location.last;
    _event = EventLog(
      // Same id as the background service uses, so a takeover updates its entry.
      id: snap.triggeredAt!.millisecondsSinceEpoch.toString(),
      time: snap.triggeredAt!,
      trigger: snap.source!.name,
      lat: loc?.lat,
      lng: loc?.lng,
    );
    // Voice cancel must work without a tap, so listen during the countdown.
    if (!services.voice.listening) unawaited(startListening());
    _onCountdown(snap);
  }

  void _onCountdown(AlertSnapshot snap) {
    services.device.vibrate();
    final n = snap.remaining;
    if (n == settings.cancelWindowSeconds || n == 10 || n == 5) {
      _speak(countdownPrompt(settings.language, n), settings.language, clip: 'countdown-$n');
    }
  }

  void _onActivated(AlertSnapshot snap) {
    services.speech.stop();
    final loc = services.location.last;
    _details = AlertDetails(
      status: AlertStatus.active,
      trigger: snap.source!.name,
      time: snap.activatedAt!,
      lat: loc?.lat,
      lng: loc?.lng,
      name: profile.name,
      condition: profile.condition,
      seizureType: profile.seizureType,
      medications: profile.medications,
      allergies: profile.allergies,
      bloodType: profile.bloodType,
    );
    _event ??= EventLog(
      id: snap.triggeredAt!.millisecondsSinceEpoch.toString(),
      time: snap.triggeredAt!,
      trigger: snap.source!.name,
    );
    _event!
      ..outcome = 'active'
      ..lat = loc?.lat
      ..lng = loc?.lng
      ..contactsNotified = contacts.length;
    _saveEvent();

    convo.clear();
    step = 0;
    cycleLanguages = true;
    stepLang = settings.languageOrder.first;
    if (_smsSentInBackground) {
      smsStatus = 'Alert SMS already sent by background protection';
      _smsSentInBackground = false;
    } else {
      unawaited(sendAlertSms());
    }
    services.device.keepScreenOn(true);
    _runLoop();
  }

  void _onFinished(AlertSnapshot snap) {
    _loopGen++;
    services.speech.stop();
    services.device.keepScreenOn(false);
    final e = _event;
    if (e == null) return;
    e.outcome = snap.outcome!.name;
    if (snap.activatedAt != null) e.durationSeconds = snap.resolvedAt!.difference(snap.activatedAt!).inSeconds;
    _saveEvent();
    // Spec 6.2 step 4: tell contacts the alert is over.
    if (snap.outcome == AlertOutcome.resolved) unawaited(sendOkaySms());
  }

  void _saveEvent() {
    final e = _event!;
    events.removeWhere((x) => x.id == e.id);
    events.insert(0, e);
    _save();
  }

  String get dashboardLink => _details == null || dashboardBase.isEmpty ? '' : dashboardUrl(dashboardBase, _details!);

  List<String> get _numbers => [for (final c in contacts) c.phone.replaceAll(RegExp(r'[^\d+]'), '')];

  Future<void> sendAlertSms() async {
    final d = _details;
    if (d == null) return;
    if (contacts.isEmpty) {
      smsStatus = 'No emergency contacts: add them in Settings';
      notifyListeners();
      return;
    }
    final link = dashboardBase.isEmpty ? '' : dashboardUrl(dashboardBase, d);
    final result = await services.messenger.sendSms(_numbers, smsBody(d, link));
    smsStatus = switch (result) {
      SmsResult.sent => 'Alert SMS sent to ${contacts.length} contact${contacts.length == 1 ? '' : 's'}',
      SmsResult.openedComposer => 'SMS app opened: press send',
      SmsResult.failed => 'SMS failed: call for help',
    };
    notifyListeners();
  }

  Future<void> sendOkaySms() async {
    final d = _details;
    if (d == null || contacts.isEmpty) return;
    final resolved = d.resolved();
    final link = dashboardBase.isEmpty ? '' : dashboardUrl(dashboardBase, resolved);
    await services.messenger.sendSms(_numbers, smsBody(resolved, link));
  }

  Future<void> callEmergency() => services.messenger.call(emergencyNumber);

  // ------------------------------------------------------------------ bystander loop

  /// Loops the first-aid steps, one language after another, until the alert
  /// ends. Bumping _loopGen stops the current run (to answer a question).
  Future<void> _runLoop() async {
    final gen = ++_loopGen;
    while (gen == _loopGen && machine.state == AlertState.active) {
      notifyListeners();
      await _speak(firstAidSteps[stepLang]![step], stepLang, clip: 'step-${step + 1}');
      if (gen != _loopGen) return;
      // A pause between steps is when a bystander can most easily be heard.
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (gen != _loopGen) return;
      step = (step + 1) % firstAidSteps[Lang.en]!.length;
      if (step == 0 && cycleLanguages) {
        final order = settings.languageOrder;
        stepLang = order[(order.indexOf(stepLang) + 1) % order.length];
      }
    }
  }

  Future<void> _interrupt(Future<void> Function() fn) async {
    _loopGen++;
    await services.speech.stop();
    await fn();
    if (machine.state == AlertState.active) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      unawaited(_runLoop());
    }
  }

  void setBystanderLang(Lang? lang) {
    cycleLanguages = lang == null;
    if (lang != null) stepLang = lang;
    notifyListeners();
    _interrupt(() async {});
  }

  void _answerBystander(IntentMatch? match) {
    final lang = match?.lang ?? stepLang;
    // [clip] plays the recorded Amharic/Oromo audio when there is one;
    // [spoken] is what to say if it differs from the text shown.
    Future<void> reply(String msg, {String? clip, String? spoken}) {
      convo.insert(0, ConvoLine(false, msg));
      notifyListeners();
      return _speak(spoken ?? msg, lang, clip: clip);
    }

    _interrupt(() async {
      final steps = firstAidSteps[lang]!;
      switch (match?.intent) {
        case null:
          return reply(answerNotUnderstood[lang]!, clip: 'answer-notUnderstood');
        case Intent.elapsed:
          final secs = machine.elapsed;
          // Clips exist per whole minute; the exact time is shown on screen.
          final minutes = (secs ~/ 60).clamp(0, 30);
          await reply(
            answerElapsed(lang, secs),
            clip: 'elapsed-$minutes',
            spoken: lang == Lang.en ? null : elapsedSpoken(lang, minutes),
          );
          if (secs >= 300) await reply(answerOverFiveMinutes[lang]!, clip: 'answer-overFiveMinutes');
        case Intent.whatToDo:
        case Intent.repeat:
          stepLang = lang;
          return reply(steps[step], clip: 'step-${step + 1}');
        case Intent.nextStep:
          stepLang = lang;
          step = (step + 1) % steps.length;
          return reply(steps[step], clip: 'step-${step + 1}');
        case Intent.callHelp:
          await reply(answerCalling[lang]!, clip: 'answer-calling');
          await callEmergency();
        case Intent.medicalInfo:
          return reply(answerMedical(
            lang,
            name: profile.name,
            condition: profile.condition,
            medications: profile.medications,
            allergies: profile.allergies,
          ));
        case Intent.cancel:
          return reply(answerHoldToStop[lang]!, clip: 'answer-holdToStop');
        case Intent.trigger:
          break;
      }
    });
  }

  // ------------------------------------------------------------------ edits

  void updateProfile(void Function(UserProfile p) edit) {
    edit(profile);
    _save();
    notifyListeners();
  }

  void addContact(EmergencyContact c) {
    if (contacts.length >= 5) return;
    contacts.add(c);
    _save();
    notifyListeners();
  }

  void removeContact(int index) {
    contacts.removeAt(index);
    _save();
    notifyListeners();
  }

  void updateSettings(void Function(AppSettings s) edit) {
    final hadFall = settings.fallDetection;
    edit(settings);
    machine.cancelWindowSeconds = settings.cancelWindowSeconds;
    detector.sensitivity = settings.sensitivity;
    if (hadFall != settings.fallDetection) _applyFallDetection();
    _save().then((_) {
      services.background.reload();
      _applyBackgroundProtection();
    });
    notifyListeners();
  }

  String eventsCsv() => [EventLog.csvHeader, ...events.map((e) => e.toCsvRow())].join('\n');
}
