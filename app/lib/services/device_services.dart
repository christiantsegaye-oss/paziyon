import 'dart:async';

import 'package:another_telephony/telephony.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/content.dart';
import '../core/fall_detector.dart';
import 'background_service.dart';
import 'services.dart';
import 'voxide_bridge.dart';

AppServices deviceServices() => AppServices(
      voice: SpeechToTextVoiceInput(),
      speech: DeviceSpeechOutput(),
      location: GeolocatorLocation(),
      motion: SensorsMotion(),
      messenger: DeviceMessenger(),
      store: PrefsStore(),
      device: DeviceControlImpl(),
      background: AndroidBackgroundProtection(),
      agent: VoxideBridge(),
      siren: DeviceSiren(),
    );

/// Stand-in for Voxide until the day-1 spike lands: Android's recognizer
/// through speech_to_text.
///
/// Things that matter on real phones:
///  - Partial results are passed on, because many phones end a session on
///    silence without ever sending a "final" result.
///  - Android stops listening after every pause, so it is restarted for as
///    long as listening is wanted.
///  - If the phone cannot recognize the chosen language (common for Amharic
///    and Afaan Oromo, or with no internet), it falls back to English and says
///    so, instead of silently hearing nothing.
class SpeechToTextVoiceInput implements VoiceInput {
  final _stt = SpeechToText();
  final _heard = StreamController<Heard>.broadcast();
  final _status = StreamController<VoiceStatus>.broadcast();
  bool _ready = false;
  bool _wanted = false;
  bool _starting = false;
  int _utterance = 0;
  Lang _lang = Lang.en;
  String? _localeId;
  String? _detail;
  List<String> _locales = const [];

  @override
  Stream<Heard> get heard => _heard.stream;
  @override
  Stream<VoiceStatus> get status => _status.stream;
  @override
  bool get listening => _wanted;
  @override
  String? get detail => _detail;

  void _emit(VoiceStatus s, [String? detail]) {
    _detail = detail;
    _status.add(s);
  }

  @override
  Future<bool> requestMicPermission() async {
    if (_ready) return true;
    // initialize() shows the microphone permission prompt.
    _ready = await _stt.initialize(onStatus: _onStatus, onError: _onError);
    if (_ready) {
      _locales = (await _stt.locales()).map((l) => l.localeId.replaceAll('-', '_').toLowerCase()).toList();
    }
    return _ready;
  }

  @override
  Future<void> start(Lang lang) async {
    _lang = lang;
    _wanted = true;
    if (!_ready) {
      _ready = await _stt.initialize(onStatus: _onStatus, onError: _onError);
      if (!_ready) {
        _wanted = false;
        _emit(VoiceStatus.unavailable,
            'This phone has no speech recognizer, or the microphone is blocked. Install or enable Google speech services.');
        return;
      }
      _locales = (await _stt.locales()).map((l) => l.localeId.replaceAll('-', '_').toLowerCase()).toList();
    }
    _localeId = _pickLocale(lang);
    if (_stt.isListening) await _stt.cancel();
    await _listen();
  }

  /// Always tries the requested language: phones often leave languages they
  /// can recognize online (Amharic with Google) off the list. Real errors and
  /// repeated non-matches fall back to English (see _onError).
  String _pickLocale(Lang lang) {
    _noMatchStreak = 0;
    final wanted = lang.tag.replaceAll('-', '_');
    final base = wanted.split('_').first.toLowerCase();
    final listed = _locales.isEmpty || _locales.any((l) => l == wanted.toLowerCase() || l.startsWith('${base}_') || l == base);
    _detail = listed || lang == Lang.en
        ? null
        : 'This phone may not recognize ${lang.label}. If it hears nothing, it will switch to English.';
    return wanted;
  }

  // Speech heard but never matched in a non-English language usually means
  // the phone cannot recognize that language at all.
  int _noMatchStreak = 0;

  void _fallBackToEnglish(String why) {
    if (_localeId == 'en_US') return;
    _localeId = 'en_US';
    _noMatchStreak = 0;
    _emit(VoiceStatus.error, '$why It now listens in English. You can still type ${_lang.label} phrases.');
    if (_stt.isListening) _stt.cancel();
  }

  void _onStatus(String s) {
    if (s == SpeechToText.listeningStatus) {
      _emit(VoiceStatus.listening, _detail);
    } else if ((s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) && _wanted) {
      // Restart after each pause; short delay avoids "recognizer busy".
      Future.delayed(const Duration(milliseconds: 400), _listen);
    }
  }

  void _onError(SpeechRecognitionError e) {
    switch (e.errorMsg) {
      case 'error_permission' || 'error_insufficient_permissions':
        _wanted = false;
        _emit(VoiceStatus.denied, 'Microphone permission is off. Allow it in Settings → Apps → P.A.Z.I.Y.O.N → Permissions.');
      case 'error_language_not_supported' || 'error_language_unavailable':
        _fallBackToEnglish('${_lang.label} speech recognition is not available on this phone.');
      case 'error_no_match' when _localeId != 'en_US':
        if (++_noMatchStreak >= 3) {
          _fallBackToEnglish('This phone heard speech but could not recognize ${_lang.label}.');
        }
      case 'error_network' || 'error_network_timeout' || 'error_server_disconnected':
        _emit(VoiceStatus.error, 'Speech recognition for ${_lang.label} needs internet on this phone. English may work offline.');
      default:
        // no_match / speech_timeout / busy / client happen between phrases; onStatus restarts.
        break;
    }
  }

  Future<void> _listen() async {
    if (!_wanted || _starting || _stt.isListening) return;
    _starting = true;
    final utterance = ++_utterance;
    try {
      await _stt.listen(
        onResult: (r) {
          if (r.recognizedWords.isNotEmpty) {
            _noMatchStreak = 0;
            _heard.add(Heard(r.recognizedWords, isFinal: r.finalResult, utterance: utterance));
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      _emit(VoiceStatus.error, 'Could not start listening. Tap Start listening to try again.');
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    await _stt.cancel();
    _emit(VoiceStatus.off);
  }
}

/// Recorded clips when bundled, otherwise text-to-speech. Most phones have no
/// Amharic or Afaan Oromo voice, which is why the recordings matter; without
/// either, the text stays on screen for a reading-length pause.
class DeviceSpeechOutput implements SpeechOutput {
  final _tts = FlutterTts();
  final _player = AudioPlayer();
  final _missingClips = <String>{};
  final _voiceAvailable = <Lang, bool>{};
  Completer<void>? _pause;

  DeviceSpeechOutput() {
    _tts.awaitSpeakCompletion(true);
    _tts.setVolume(1);
    _tts.setSpeechRate(0.45);
  }

  @override
  Future<void> say(String text, Lang lang, {String? clip}) async {
    await stop();
    if (clip != null) {
      final path = 'audio/${lang.name}/$clip.mp3';
      if (!_missingClips.contains(path)) {
        try {
          await rootBundle.load('assets/$path');
          await _player.setVolume(1);
          _pause = Completer<void>();
          await _player.play(AssetSource(path));
          // Ends when the clip finishes or stop() interrupts it.
          await Future.any([_player.onPlayerComplete.first, _pause!.future]);
          return;
        } catch (_) {
          _missingClips.add(path);
        }
      }
    }
    final available = _voiceAvailable[lang] ??= (await _tts.isLanguageAvailable(lang.tag)) == true;
    if (available) {
      await _tts.setLanguage(lang.tag);
      await _tts.speak(text);
    } else {
      _pause = Completer<void>();
      final ms = (1500 + text.length * 60).clamp(0, 8000);
      await Future.any([Future<void>.delayed(Duration(milliseconds: ms)), _pause!.future]);
    }
  }

  @override
  Future<void> stop() async {
    if (_pause?.isCompleted == false) _pause!.complete();
    await _tts.stop();
    await _player.stop();
  }
}

/// Keeps the last known position so an alert always has something to send.
class GeolocatorLocation implements LocationProvider {
  LatLng? _last;
  StreamSubscription<Position>? _sub;

  @override
  LatLng? get last => _last;

  @override
  Future<void> start() async {
    if (_sub != null) return;
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    final known = await Geolocator.getLastKnownPosition();
    if (known != null) _set(known);
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen(_set, onError: (_) {});
  }

  void _set(Position p) => _last = (
        lat: double.parse(p.latitude.toStringAsFixed(5)),
        lng: double.parse(p.longitude.toStringAsFixed(5)),
      );
}

class SensorsMotion implements MotionSource {
  @override
  Stream<MotionSample>? samples() => accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
      .map((e) => MotionSample(e.timestamp.millisecondsSinceEpoch, e.x, e.y, e.z));
}

/// Sends SMS directly from the phone — no data connection or backend needed
/// (spec 6.3). Falls back to the SMS app if permission is refused.
class DeviceMessenger implements Messenger {
  final _telephony = Telephony.instance;

  @override
  Future<SmsResult> sendSms(List<String> to, String body) async {
    final granted = to.isNotEmpty && (await _telephony.requestSmsPermissions ?? false);
    if (granted) {
      try {
        for (final number in to) {
          await _telephony.sendSms(to: number, message: body, isMultipart: true);
        }
        return SmsResult.sent;
      } catch (_) {
        // fall through to the composer
      }
    }
    final uri = Uri(scheme: 'sms', path: to.join(','), queryParameters: {'body': body});
    return await launchUrl(uri) ? SmsResult.openedComposer : SmsResult.failed;
  }

  @override
  Future<void> call(String number) => launchUrl(Uri(scheme: 'tel', path: number));
}

class PrefsStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // the background service writes from another isolate
    return prefs.getString(key);
  }
  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
  @override
  Future<void> delete(String key) async => (await SharedPreferences.getInstance()).remove(key);
}

class DeviceControlImpl implements DeviceControl {
  @override
  Future<void> keepScreenOn(bool on) => on ? WakelockPlus.enable() : WakelockPlus.disable();
  @override
  Future<void> vibrate() => HapticFeedback.vibrate();
}

/// The alert siren: a generated wail (tools/generate_siren.py) looped on the
/// alarm channel. While it plays, the alarm and media volumes are turned to
/// maximum and restored afterwards.
class DeviceSiren implements Siren {
  final _player = AudioPlayer();
  bool _playing = false;
  Completer<void>? _done;
  Timer? _timer;
  double? _alarmVolume, _mediaVolume;
  bool _ready = false;

  @override
  bool get playing => _playing;

  Future<void> _setUp() async {
    if (_ready) return;
    _ready = true;
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.sonification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    ));
    await _player.setReleaseMode(ReleaseMode.loop);
  }

  Future<void> _maxVolume() async {
    try {
      _alarmVolume ??= await FlutterVolumeController.getVolume(stream: AudioStream.alarm);
      _mediaVolume ??= await FlutterVolumeController.getVolume(stream: AudioStream.music);
      await FlutterVolumeController.setVolume(1, stream: AudioStream.alarm);
      await FlutterVolumeController.setVolume(1, stream: AudioStream.music);
    } catch (_) {
      // Some phones refuse volume changes (e.g. in Do Not Disturb); play anyway.
    }
  }

  Future<void> _restoreVolume() async {
    try {
      if (_alarmVolume != null) await FlutterVolumeController.setVolume(_alarmVolume!, stream: AudioStream.alarm);
      if (_mediaVolume != null) await FlutterVolumeController.setVolume(_mediaVolume!, stream: AudioStream.music);
    } catch (_) {}
    _alarmVolume = _mediaVolume = null;
  }

  @override
  Future<void> play({Duration? duration}) async {
    await _setUp();
    await _maxVolume();
    _done ??= Completer<void>();
    final done = _done!;
    if (!_playing) {
      _playing = true;
      await _player.setVolume(1);
      await _player.play(AssetSource('audio/siren.wav'));
    }
    _timer?.cancel();
    if (duration != null) _timer = Timer(duration, () => _pause());
    return done.future;
  }

  /// Ends one burst but keeps the raised volume for the next.
  Future<void> _pause() async {
    _timer?.cancel();
    _playing = false;
    await _player.pause();
    final d = _done;
    _done = null;
    if (d != null && !d.isCompleted) d.complete();
  }

  @override
  Future<void> stop() async {
    await _pause();
    await _restoreVolume();
  }
}
