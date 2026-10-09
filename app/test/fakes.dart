import 'dart:async';

import 'package:seizure_alert/core/content.dart';
import 'package:seizure_alert/core/fall_detector.dart';
import 'package:seizure_alert/services/services.dart';

class FakeVoice implements VoiceInput {
  final _h = StreamController<Heard>.broadcast();
  final _s = StreamController<VoiceStatus>.broadcast();
  bool _listening = false;
  int _utterance = 0;
  Lang? lang;
  @override
  String? detail;

  /// What the microphone "hears", as one finished utterance.
  void hear(String text) => _h.add(Heard(text, isFinal: true, utterance: ++_utterance));

  /// Partial results of one utterance, as a real recognizer sends them,
  /// optionally with no final result at all (common on real phones).
  void hearPartials(List<String> partials, {bool finalResult = true}) {
    final u = ++_utterance;
    for (var i = 0; i < partials.length; i++) {
      _h.add(Heard(partials[i], isFinal: finalResult && i == partials.length - 1, utterance: u));
    }
  }

  void fail(VoiceStatus status, String why) {
    detail = why;
    _s.add(status);
  }

  @override
  Stream<Heard> get heard => _h.stream;
  @override
  Stream<VoiceStatus> get status => _s.stream;
  @override
  bool get listening => _listening;
  @override
  Future<void> start(Lang lang) async {
    this.lang = lang;
    _listening = true;
    _s.add(VoiceStatus.listening);
  }

  @override
  Future<void> stop() async {
    _listening = false;
    _s.add(VoiceStatus.off);
  }
}

class FakeSpeech implements SpeechOutput {
  final said = <(String, Lang)>[];
  @override
  Future<void> say(String text, Lang lang, {String? clip}) async => said.add((text, lang));
  @override
  Future<void> stop() async {}
}

class FakeLocation implements LocationProvider {
  @override
  LatLng? get last => (lat: 9.0301, lng: 38.7408);
  @override
  Future<void> start() async {}
}

class NoMotion implements MotionSource {
  @override
  Stream<MotionSample>? samples() => null;
}

class FakeMessenger implements Messenger {
  final sms = <(List<String>, String)>[];
  final calls = <String>[];
  @override
  Future<SmsResult> sendSms(List<String> to, String body) async {
    sms.add((to, body));
    return SmsResult.sent;
  }

  @override
  Future<void> call(String number) async => calls.add(number);
}

class MemoryStore implements KeyValueStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

class FakeDevice implements DeviceControl {
  bool screenOn = false;
  @override
  Future<void> keepScreenOn(bool on) async => screenOn = on;
  @override
  Future<void> vibrate() async {}
}

class FakeBackground implements BackgroundProtection {
  bool running = false;
  int heartbeats = 0;
  Map<Object?, Object?>? pending;
  final _falls = StreamController<void>.broadcast();
  final _actions = StreamController<String>.broadcast();

  void detectFallWhileAppOnScreen() => _falls.add(null);
  void notificationTapped(String action) => _actions.add(action);

  @override
  Future<void> start() async => running = true;
  @override
  Future<void> stop() async => running = false;
  @override
  void reload() {}
  @override
  void heartbeat() => heartbeats++;
  @override
  void hidden() {}
  @override
  Stream<void> get forwardedFalls => _falls.stream;
  @override
  Stream<String> get notificationActions => _actions.stream;
  @override
  Future<Map<Object?, Object?>?> takeOver() async {
    final p = pending;
    pending = null;
    return p;
  }
}
