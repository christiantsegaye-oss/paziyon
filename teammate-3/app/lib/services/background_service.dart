import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:another_telephony/telephony.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:power_trigger/power_trigger.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/alert_message.dart';
import '../core/alert_state_machine.dart';
import '../core/background_coordinator.dart';
import '../core/content.dart';
import '../core/fall_detector.dart';
import '../core/power_press.dart';
import '../ui/theme.dart' show appName;
import '../models.dart';
import 'services.dart';

// Android foreground service that keeps fall detection running with the app
// closed or the screen off. The decisions live in BackgroundCoordinator; this
// file connects it to the sensor, notifications, SMS and speech.
//
// Voice triggering is not available here: Android only allows the speech
// recognizer while the app is on screen.

const _protectionChannel = AndroidNotificationChannel(
  'protection',
  'Protection status',
  description: 'Shown while fall detection runs in the background',
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
);

const _alertChannel = AndroidNotificationChannel(
  'fall_alert',
  'Fall alerts',
  description: 'Countdown and alert after a detected fall',
  importance: Importance.max,
  audioAttributesUsage: AudioAttributesUsage.alarm,
);

const _alertNotificationId = 2;
const _serviceNotificationId = 1;

final _notifications = FlutterLocalNotificationsPlugin();

/// Notification buttons: 'cancel' (I'm okay), 'help' (Get help now), else 'open'.
String _action(String? id) => id == 'cancel' || id == 'help' ? id! : 'open';

class AndroidBackgroundProtection implements BackgroundProtection {
  final _service = FlutterBackgroundService();
  final _actions = StreamController<String>.broadcast();
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    final android =
        _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await _notifications.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => _actions.add(_action(r.actionId)),
    );
    await android?.createNotificationChannel(_protectionChannel);
    await android?.createNotificationChannel(_alertChannel);
    await android?.requestNotificationsPermission();

    // Opened from a notification while the app was not running.
    final launch = await _notifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final id = launch!.notificationResponse?.actionId;
      scheduleMicrotask(() => _actions.add(_action(id)));
    }

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundMain,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _protectionChannel.id,
        foregroundServiceNotificationId: _serviceNotificationId,
        initialNotificationTitle: '$appName is protecting you',
        initialNotificationContent: 'Press the power button 3 times for help',
        foregroundServiceTypes: [AndroidForegroundType.health],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  @override
  Future<void> start() async {
    await _configure();
    if (!await _service.isRunning()) await _service.startService();
  }

  @override
  Future<void> stop() async {
    await _configure();
    if (await _service.isRunning()) _service.invoke('stop');
  }

  @override
  void reload() => _service.invoke('reload');
  @override
  void heartbeat() => _service.invoke('heartbeat');
  @override
  void hidden() => _service.invoke('hidden');

  @override
  Stream<void> get forwardedFalls => _service.on('fall');
  @override
  Stream<String> get notificationActions => _actions.stream;

  @override
  Future<Map<Object?, Object?>?> takeOver() async {
    await _configure();
    if (!await _service.isRunning()) return null;
    final reply = _service.on('handedOver').first.timeout(const Duration(seconds: 2), onTimeout: () => null);
    _service.invoke('handOver');
    final data = await reply;
    return (data == null || data.isEmpty) ? null : data;
  }
}

class _Stored {
  _Stored(this.profile, this.contacts, this.settings);
  final UserProfile profile;
  final List<EmergencyContact> contacts;
  final AppSettings settings;
}

Future<_Stored> _readStore() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // the app writes from another isolate
  final raw = prefs.getString(storeKey);
  if (raw == null) return _Stored(UserProfile(), [], AppSettings());
  final j = jsonDecode(raw) as Map<String, dynamic>;
  return _Stored(
    UserProfile.fromJson(j['profile'] as Map<String, dynamic>? ?? {}),
    [for (final c in j['contacts'] as List? ?? []) EmergencyContact.fromJson(c as Map<String, dynamic>)],
    AppSettings.fromJson(j['settings'] as Map<String, dynamic>? ?? {}),
  );
}

/// Records an alert the service sent, so it shows in History even if the app
/// is never opened. Same id format as the app, so a later takeover updates it.
Future<void> _logEvent(EventLog e) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final raw = prefs.getString(storeKey);
  final j = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
  final events = [for (final x in j['events'] as List? ?? []) x as Map<String, dynamic>]
    ..removeWhere((x) => x['id'] == e.id)
    ..insert(0, e.toJson());
  j['events'] = events;
  await prefs.setString(storeKey, jsonEncode(j));
}

@pragma('vm:entry-point')
Future<void> backgroundMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await _notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );
  final tts = FlutterTts()..awaitSpeakCompletion(true);
  final player = AudioPlayer();
  final siren = AudioPlayer()
    ..setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.sonification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    ))
    ..setReleaseMode(ReleaseMode.loop);

  var stored = await _readStore();
  var speakGen = 0;

  // Loud siren to draw people over (same sound as the app).
  Future<void> sirenBurst(Duration d) async {
    if (!stored.settings.siren) return;
    try {
      await FlutterVolumeController.setVolume(1, stream: AudioStream.alarm);
    } catch (_) {}
    await siren.play(AssetSource('audio/siren.wav'), volume: 1);
    await Future<void>.delayed(d);
    await siren.pause();
  }

  // Recorded clip first (phones have no Amharic/Oromo voice), then TTS.
  Future<void> say(String text, Lang lang, {String? clip}) async {
    if (clip != null && lang != Lang.en) {
      try {
        await player.play(AssetSource('audio/${lang.name}/$clip.mp3'));
        await player.onPlayerComplete.first.timeout(const Duration(seconds: 20));
        return;
      } catch (_) {
        // fall through to TTS
      }
    }
    try {
      if (await tts.isLanguageAvailable(lang.tag) == true) {
        await tts.setLanguage(lang.tag);
        await tts.setVolume(1);
        await tts.speak(text);
      } else {
        await Future<void>.delayed(const Duration(seconds: 4));
      }
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  }

  // First-aid steps for anyone nearby, even if nobody opens the app. Stops
  // after 10 minutes or when the app takes over.
  Future<void> speakFirstAid() async {
    final gen = ++speakGen;
    final end = DateTime.now().add(const Duration(minutes: 10));
    await sirenBurst(const Duration(seconds: 6));
    while (gen == speakGen && DateTime.now().isBefore(end)) {
      for (final lang in stored.settings.languageOrder) {
        for (final (i, step) in firstAidSteps[lang]!.indexed) {
          if (gen != speakGen) return;
          await say(step, lang, clip: 'step-${i + 1}');
          if (gen != speakGen) return;
          await sirenBurst(const Duration(seconds: 3));
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }
      }
    }
  }

  late final BackgroundCoordinator coordinator;
  final detector = FallDetector(
    sensitivity: stored.settings.sensitivity,
    onFall: (_) => coordinator.fall(),
  );

  coordinator = BackgroundCoordinator(
    machine: AlertStateMachine(cancelWindowSeconds: stored.settings.cancelWindowSeconds),
    onForwardToApp: () => service.invoke('fall'),
    onCountdown: (n) {
      final loud = n == stored.settings.cancelWindowSeconds || n == 10 || n == 5;
      _notifications.show(
        id: _alertNotificationId,
        title: coordinator.machine.snapshot().source == TriggerSource.fall ? 'Fall detected' : 'Help requested',
        body: 'Alert sends to your contacts in $n s. Open the app, or tap I’m okay.',
        payload: 'countdown',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _alertChannel.id,
            _alertChannel.name,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            ongoing: true,
            onlyAlertOnce: !loud,
            actions: const [
              AndroidNotificationAction('cancel', 'I’m okay — cancel', showsUserInterface: true),
            ],
          ),
        ),
      );
      if (loud) say(countdownPrompt(stored.settings.language, n), stored.settings.language, clip: 'countdown-$n');
    },
    onSendAlert: (snap) async {
      stored = await _readStore();
      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 10));
      } catch (_) {}
      final lat = pos == null ? null : double.parse(pos.latitude.toStringAsFixed(5));
      final lng = pos == null ? null : double.parse(pos.longitude.toStringAsFixed(5));
      final p = stored.profile;
      final details = AlertDetails(
        status: AlertStatus.active,
        trigger: snap.source!.name,
        time: snap.activatedAt!,
        lat: lat,
        lng: lng,
        name: p.name,
        condition: p.condition,
        seizureType: p.seizureType,
        medications: p.medications,
        allergies: p.allergies,
        bloodType: p.bloodType,
      );
      final body = smsBody(details, dashboardBase.isEmpty ? '' : dashboardUrl(dashboardBase, details));
      var sent = 0;
      for (final c in stored.contacts) {
        try {
          await Telephony.backgroundInstance
              .sendSms(to: c.phone.replaceAll(RegExp(r'[^\d+]'), ''), message: body, isMultipart: true);
          sent++;
        } catch (e) {
          debugPrint('SMS to contact failed: $e');
        }
      }
      await _logEvent(EventLog(
        id: snap.triggeredAt!.millisecondsSinceEpoch.toString(),
        time: snap.triggeredAt!,
        trigger: snap.source!.name,
        outcome: 'active',
        lat: lat,
        lng: lng,
        contactsNotified: sent,
      ));
      await _notifications.show(
        id: _alertNotificationId,
        title: 'MEDICAL EMERGENCY — PLEASE HELP',
        body: 'Alert sent to $sent contact${sent == 1 ? '' : 's'}. Open for first-aid instructions and medical ID.',
        payload: 'alert',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _alertChannel.id,
            _alertChannel.name,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            ongoing: true,
          ),
        ),
      );
      unawaited(speakFirstAid());
    },
    onClear: () {
      speakGen++;
      tts.stop();
      player.stop();
      siren.stop();
      _notifications.cancel(id: _alertNotificationId);
    },
  );

  // Replaces the service's plain status notification (same id) with one that
  // has a button, so help is one tap away on the lock screen.
  await _notifications.show(
    id: _serviceNotificationId,
    title: '$appName is protecting you',
    body: 'Press the power button 3 times, or tap Get help now.',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _protectionChannel.id,
        _protectionChannel.name,
        importance: Importance.low,
        ongoing: true,
        visibility: NotificationVisibility.public,
        actions: const [AndroidNotificationAction('help', 'Get help now', showsUserInterface: true)],
      ),
    ),
  );

  // Three quick power-button presses start the alert with the phone locked.
  final presses = PowerPressDetector(onTriggered: () {
    if (coordinator.machine.state == AlertState.idle) coordinator.manualTrigger();
  });
  final screen = screenToggles().listen(presses.toggle, onError: (_) {});

  final motion = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
    if (stored.settings.fallDetection && coordinator.machine.state == AlertState.idle) {
      detector.push(MotionSample(e.timestamp.millisecondsSinceEpoch, e.x, e.y, e.z));
    }
  }, onError: (_) {});
  final ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => coordinator.tick());

  service.on('heartbeat').listen((_) => coordinator.appHeartbeat());
  service.on('hidden').listen((_) => coordinator.appHidden());
  service.on('cancel').listen((_) => coordinator.cancel());
  service.on('handOver').listen((_) => service.invoke('handedOver', {...?coordinator.handOver()}));
  service.on('reload').listen((_) async {
    stored = await _readStore();
    detector.sensitivity = stored.settings.sensitivity;
    coordinator.machine.cancelWindowSeconds = stored.settings.cancelWindowSeconds;
  });
  service.on('stop').listen((_) async {
    await motion.cancel();
    await screen.cancel();
    ticker.cancel();
    await service.stopSelf();
  });
}
