import '../core/content.dart';
import '../core/fall_detector.dart';

// The app talks to the phone only through these interfaces, so the controller
// and the UI can be tested with fakes and the voice engine can be swapped
// (Voxide replaces the speech_to_text stand-in without touching the rest).

typedef LatLng = ({double lat, double lng});

enum VoiceStatus { off, listening, denied, unavailable, error }

/// Something the recognizer heard. Partial results arrive while the person is
/// still speaking; [utterance] stays the same until they pause, so the app can
/// act on the first partial that matches and ignore the rest.
class Heard {
  const Heard(this.text, {required this.isFinal, required this.utterance});
  final String text;
  final bool isFinal;
  final int utterance;
}

abstract class VoiceInput {
  /// Asks for the microphone permission (Voxide needs it too) without
  /// starting to listen. Returns whether it was granted.
  Future<bool> requestMicPermission();
  Stream<Heard> get heard;
  Stream<VoiceStatus> get status;
  bool get listening;

  /// Why voice is not working, or which language is really being used, in
  /// words for the screen. Null when all is well.
  String? get detail;
  Future<void> start(Lang lang);
  Future<void> stop();
}

/// Voxide (voxide.app): the live voice agent. It listens and speaks naturally
/// in Amharic, Afaan Oromo and English, and calls the app's capabilities
/// (start_emergency_alert, cancel_alert, get_first_aid_step, ...). See
/// app/assets/voxide/paziyon-voxide.js for the capability list.
enum AgentStatus { off, connecting, listening, thinking, speaking, executing, error }

class AgentToolCall {
  const AgentToolCall(this.id, this.name, this.args);
  final int id;
  final String name;
  final Map<String, Object?> args;
}

abstract class VoiceAgent {
  AgentStatus get status;
  Stream<AgentStatus> get statusChanges;

  /// What the person is saying (partial while speaking, then final).
  Stream<Heard> get heard;

  /// Each finished thing the agent said.
  Stream<String> get said;
  Stream<AgentToolCall> get toolCalls;
  Stream<String> get errors;

  Future<void> start({required String key, required Lang lang});
  Future<void> stop();
  void setLanguage(Lang lang);

  /// App state the agent sees on every turn.
  void setState(Map<String, Object?> state);
  void resolveTool(int id, Map<String, Object?> result);

  /// Has the agent read [text] aloud in [lang], in its natural voice.
  /// Completes when it has finished; false if the agent is not connected,
  /// so the caller falls back to the bundled clips.
  Future<bool> say(String text, Lang lang);

  /// Stops the agent mid-sentence.
  void interrupt();
}

/// The loud siren that draws people's attention to an alert.
abstract class Siren {
  bool get playing;

  /// Plays at full volume on the alarm channel, for [duration] or until
  /// stopped. Completes when it stops.
  Future<void> play({Duration? duration});
  Future<void> stop();
}

abstract class SpeechOutput {
  /// Speaks [text], or plays the recorded clip `assets/audio/<lang>/<clip>.mp3`
  /// when it exists. Completes when finished or stopped.
  Future<void> say(String text, Lang lang, {String? clip});
  Future<void> stop();
}

abstract class LocationProvider {
  Future<void> start();
  LatLng? get last;
}

abstract class MotionSource {
  /// Accelerometer readings including gravity. Null when there is no sensor.
  Stream<MotionSample>? samples();
}

enum SmsResult { sent, openedComposer, failed }

abstract class Messenger {
  /// Sends directly when SMS permission is granted, otherwise opens the SMS app.
  Future<SmsResult> sendSms(List<String> to, String body);
  Future<void> call(String number);
}

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

abstract class DeviceControl {
  Future<void> keepScreenOn(bool on);
  Future<void> vibrate();
}

/// Fall detection that keeps running with the app closed or the screen off
/// (spec 5.2 TriggerService). See core/background_coordinator.dart for the rules.
abstract class BackgroundProtection {
  Future<void> start();
  Future<void> stop();

  /// Tell the service to re-read settings, profile and contacts.
  void reload();

  /// The app is on screen; call every few seconds while it is.
  void heartbeat();
  void hidden();

  /// Falls the service detected while the app was on screen.
  Stream<void> get forwardedFalls;

  /// Notification taps: 'open', 'cancel' ("I'm okay") or 'help' ("Get help now").
  Stream<String> get notificationActions;

  /// Takes over a background countdown or alert, if any. See
  /// BackgroundCoordinator.handOver for the format.
  Future<Map<Object?, Object?>?> takeOver();
}

class AppServices {
  const AppServices({
    required this.voice,
    required this.speech,
    required this.location,
    required this.motion,
    required this.messenger,
    required this.store,
    required this.device,
    required this.background,
    required this.agent,
    required this.siren,
  });

  final VoiceInput voice;
  final SpeechOutput speech;
  final LocationProvider location;
  final MotionSource motion;
  final Messenger messenger;
  final KeyValueStore store;
  final DeviceControl device;
  final BackgroundProtection background;
  final VoiceAgent agent;
  final Siren siren;
}
