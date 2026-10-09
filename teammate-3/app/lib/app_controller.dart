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
    final agent = services.agent;
    _subs.add(agent.statusChanges.listen((s) {
      agentStatus = s;
      if (agentLive) agentError = null;
      _agentStatusWaiters.toList().forEach((w) => w(s));
      notifyListeners();
    }));
    _subs.add(agent.errors.listen((e) {
      agentError = e;
      notifyListeners();
    }));
    _subs.add(agent.heard.listen(_onAgentHeard));
    _subs.add(agent.said.listen((text) {
      // Answers to bystanders go in the conversation; read-aloud steps don't.
      if (machine.state != AlertState.active || _agentReading > 0 || text.trim().isEmpty) return;
      convo.insert(0, ConvoLine(false, text));
      notifyListeners();
    }));
    _subs.add(agent.toolCalls.listen((call) => agent.resolveTool(call.id, handleAgentTool(call))));

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
    if (onboarded) unawaited(_syncVoice());
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

  bool _disposed = false;

  // Voice engines start and stop asynchronously and may finish after the app
  // has torn the controller down.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
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
    await _syncVoice();
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

  // Voxide (voxide.app) is the voice of the app when a key is set: it hears
  // and speaks Amharic, Afaan Oromo and English naturally and calls the
  // capabilities in handleAgentTool. The phone's own recognizer and the
  // bundled clips are the fallback when there is no key or no connection.

  /// From Settings, or built in with --dart-define=VOXIDE_KEY=vox_pub_….
  String get voxideKey =>
      settings.voxideKey.trim().isNotEmpty ? settings.voxideKey.trim() : const String.fromEnvironment('VOXIDE_KEY');
  bool get voxideConfigured => voxideKey.startsWith('vox_pub_');

  AgentStatus agentStatus = AgentStatus.off;
  String? agentError;
  bool _agentStarted = false;
  bool _voiceStopped = false;
  final _agentStatusWaiters = <void Function(AgentStatus)>{};

  bool get agentLive => const {
        AgentStatus.listening,
        AgentStatus.thinking,
        AgentStatus.speaking,
        AgentStatus.executing,
      }.contains(agentStatus);

  /// Voxide holds the microphone (rather than the phone's recognizer).
  bool get usingVoxide => _agentStarted;

  /// Whether any voice engine is listening.
  bool get listening => _agentStarted || services.voice.listening;

  /// Voxide runs during every countdown and alert, and while idle when
  /// "listen with Voxide" is on. Only one engine holds the microphone.
  bool get _wantAgent =>
      voxideConfigured &&
      onboarded &&
      !_voiceStopped &&
      (machine.state != AlertState.idle || settings.voxideAlwaysListen);

  Future<void> _syncVoice() async {
    if (_wantAgent) {
      if (!_agentStarted) {
        _agentStarted = true;
        if (services.voice.listening) await services.voice.stop();
        await services.voice.requestMicPermission();
        await services.agent.start(key: voxideKey, lang: listenLang);
        _pushAgentState();
      }
    } else {
      if (_agentStarted) {
        _agentStarted = false;
        await services.agent.stop();
      }
      final wantPhone = !_voiceStopped && (settings.voiceTrigger || machine.state == AlertState.countdown);
      if (wantPhone && !services.voice.listening) {
        await services.voice.start(listenLang);
      } else if (!wantPhone && services.voice.listening) {
        await services.voice.stop();
      }
    }
    notifyListeners();
  }

  Future<void> startListening() {
    _voiceStopped = false;
    return _syncVoice();
  }

  Future<void> stopListening() async {
    _voiceStopped = true;
    if (_agentStarted) {
      _agentStarted = false;
      await services.agent.stop();
    }
    await services.voice.stop();
    notifyListeners();
  }

  Future<void> setListenLang(Lang lang) async {
    listenLang = lang;
    notifyListeners();
    if (_agentStarted) {
      services.agent.setLanguage(lang);
    } else if (services.voice.listening) {
      await services.voice.start(lang);
    }
  }

  /// What the agent sees on every turn.
  void _pushAgentState() {
    if (!_agentStarted) return;
    services.agent.setState({
      'appState': machine.state.name,
      'secondsLeftToCancel': machine.state == AlertState.countdown ? machine.remaining : null,
      'secondsSinceAlert': machine.state == AlertState.active ? machine.elapsed : null,
      'firstAidStep': machine.state == AlertState.active ? step + 1 : null,
      'firstAidSteps': firstAidSteps[Lang.en]!.length,
      'patientName': profile.name,
      'contactsAlerted': smsStatus,
      'preferredLanguage': settings.language.name,
    });
  }

  /// Speech heard by Voxide. Trigger and cancel are also matched here, as a
  /// backup to the agent's own tool calls (both are idempotent). During an
  /// alert the agent answers bystanders itself, so the first-aid loop just
  /// pauses for it.
  void _onAgentHeard(Heard h) {
    if (h.text.trim().isEmpty) return;
    hearing = h.text;
    notifyListeners();
    switch (machine.state) {
      case AlertState.idle:
      case AlertState.countdown:
        if (h.utterance != _actedOnUtterance && _routeTriggerOrCancel(h.text)) _actedOnUtterance = h.utterance;
      case AlertState.active:
        if (h.isFinal) {
          convo.insert(0, ConvoLine(true, h.text));
          notifyListeners();
          _interrupt(_waitForAgentToFinish);
        }
      case AlertState.resolved:
        break;
    }
  }

  bool _routeTriggerOrCancel(String text) {
    final match = matchIntent(text, machine.state);
    if (machine.state == AlertState.idle) {
      lastHeard = text;
      if (match?.intent == Intent.trigger && settings.voiceTrigger) return machine.trigger(TriggerSource.voice);
    } else if (machine.state == AlertState.countdown && match?.intent == Intent.cancel) {
      return machine.cancel('voice');
    }
    return false;
  }

  /// Waits while the agent thinks, uses tools and answers (max 25 s).
  Future<void> _waitForAgentToFinish() {
    final done = Completer<void>();
    var busy = !const {AgentStatus.listening, AgentStatus.off, AgentStatus.error}.contains(agentStatus);
    late void Function(AgentStatus) waiter;
    final timers = <Timer>[];
    void finish() {
      _agentStatusWaiters.remove(waiter);
      for (final t in timers) {
        t.cancel();
      }
      if (!done.isCompleted) done.complete();
    }

    waiter = (s) {
      if (s == AgentStatus.thinking || s == AgentStatus.speaking || s == AgentStatus.executing) {
        busy = true;
      } else if (busy || s == AgentStatus.off || s == AgentStatus.error) {
        finish();
      }
    };
    _agentStatusWaiters.add(waiter);
    // If nothing starts within 4 s the agent chose not to answer.
    timers
      ..add(Timer(const Duration(seconds: 4), () {
        if (!busy) finish();
      }))
      ..add(Timer(const Duration(seconds: 25), finish));
    return done.future;
  }

  /// Answers a Voxide capability call. The agent reads the result aloud in
  /// the language it is speaking.
  Map<String, Object?> handleAgentTool(AgentToolCall call) {
    switch (call.name) {
      case 'start_emergency_alert':
        if (machine.state == AlertState.idle && machine.trigger(TriggerSource.voice)) {
          return {
            'ok': true,
            'message': 'Countdown started. The alert goes to emergency contacts in '
                '${settings.cancelWindowSeconds} seconds unless the person says they are okay.',
          };
        }
        return {'ok': true, 'message': 'An alert is already in progress.', ..._alertStatus()};
      case 'cancel_alert':
        if (machine.state == AlertState.countdown && machine.cancel('voice')) {
          return {'ok': true, 'message': 'Cancelled. Nothing was sent.'};
        }
        return {
          'ok': false,
          'message': machine.state == AlertState.active
              ? 'The alert was already sent. A bystander must hold the "Patient returned" button to stop it.'
              : 'No countdown is running.',
        };
      case 'get_alert_status':
        return {'ok': true, ..._alertStatus()};
      case 'get_first_aid_step':
        final lang = Lang.values.asNameMap()[call.args['language']] ?? stepLang;
        final steps = firstAidSteps[lang]!;
        if (call.args['which'] == 'next') step = (step + 1) % steps.length;
        stepLang = lang;
        notifyListeners();
        _pushAgentState();
        return {'ok': true, 'step': step + 1, 'of': steps.length, 'language': lang.name, 'text': steps[step]};
      case 'get_medical_info':
        return {
          'ok': true,
          ...profile.toJson(),
          'emergencyContacts': [for (final c in contacts) '${c.name} (${c.relationship})'],
        };
      case 'call_emergency_services':
        unawaited(callEmergency());
        return {'ok': true, 'message': 'Calling $emergencyNumber now.'};
      default:
        return {'ok': false, 'message': 'Unknown capability ${call.name}.'};
    }
  }

  Map<String, Object?> _alertStatus() => {
        'state': machine.state.name,
        if (machine.state == AlertState.countdown) 'secondsLeftToCancel': machine.remaining,
        if (machine.state == AlertState.active) ...{
          'secondsSinceAlert': machine.elapsed,
          'description': answerElapsed(Lang.en, machine.elapsed),
          'longerThanFiveMinutes': machine.elapsed >= 300,
          'currentFirstAidStep': step + 1,
        },
        'contactsAlerted': smsStatus ?? (machine.state == AlertState.active ? 'sending' : 'not yet'),
      };

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
      // Voxide's natural voice when connected; bundled clips / TTS otherwise.
      var spokenByAgent = false;
      if (agentLive) {
        _agentReading++;
        try {
          spokenByAgent = await services.agent.say(text, lang);
        } finally {
          _agentReading--;
        }
      }
      if (!spokenByAgent) await services.speech.say(text, lang, clip: clip);
    } finally {
      final i = _spoken.indexOf(entry);
      if (i >= 0) _spoken[i] = (text: text, until: _clock().add(_echoWindow));
    }
  }

  int? _actedOnUtterance;
  int _agentReading = 0;

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
        unawaited(_syncVoice());
        detector.reset();
        convo.clear();
        smsStatus = null;
        _details = null;
        _event = null;
      case AlertEvent.tick:
        if (machine.elapsed % 5 == 0) _pushAgentState();
    }
    if (snap.event != AlertEvent.tick) _pushAgentState();
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
    // Voice cancel must work without a tap, so listen during the countdown
    // (through Voxide when it is set up).
    _voiceStopped = false;
    unawaited(_syncVoice());
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
    _sirenIntroDone = false;
    sirenMuted = false;
    _runLoop();
  }

  void _onFinished(AlertSnapshot snap) {
    _loopGen++;
    services.speech.stop();
    services.siren.stop();
    if (agentLive) services.agent.interrupt();
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
  bool _sirenIntroDone = false;

  /// A bystander silenced the siren for this alert.
  bool sirenMuted = false;

  void muteSiren() {
    sirenMuted = true;
    services.siren.stop();
    notifyListeners();
  }

  /// Siren first to draw people over, then each first-aid step followed by a
  /// short siren burst and a pause in which a bystander can talk to the phone.
  Future<void> _runLoop() async {
    final gen = ++_loopGen;
    if (settings.siren && !sirenMuted && !_sirenIntroDone) {
      _sirenIntroDone = true;
      await services.siren.play(duration: const Duration(seconds: 6));
      if (gen != _loopGen) return;
    }
    while (gen == _loopGen && machine.state == AlertState.active) {
      notifyListeners();
      await _speak(firstAidSteps[stepLang]![step], stepLang, clip: 'step-${step + 1}');
      if (gen != _loopGen) return;
      if (settings.siren && !sirenMuted) {
        await services.siren.play(duration: const Duration(seconds: 3));
        if (gen != _loopGen) return;
      }
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
    // Quiet the siren so the bystander and the phone can hear each other.
    if (services.siren.playing) await services.siren.stop();
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
    final voxideBefore = (settings.voxideKey, settings.voxideAlwaysListen);
    final hadFall = settings.fallDetection;
    edit(settings);
    machine.cancelWindowSeconds = settings.cancelWindowSeconds;
    detector.sensitivity = settings.sensitivity;
    if (hadFall != settings.fallDetection) _applyFallDetection();
    _save().then((_) {
      services.background.reload();
      _applyBackgroundProtection();
    });
    if (!settings.siren && services.siren.playing) services.siren.stop();
    final voxideChanged = voxideBefore != (settings.voxideKey, settings.voxideAlwaysListen);
    if (voxideChanged && _agentStarted) {
      // New key or mode: reconnect.
      _agentStarted = false;
      unawaited(services.agent.stop().then((_) => _syncVoice()));
    } else {
      unawaited(_syncVoice());
    }
    notifyListeners();
  }

  String eventsCsv() => [EventLog.csvHeader, ...events.map((e) => e.toCsvRow())].join('\n');
}
