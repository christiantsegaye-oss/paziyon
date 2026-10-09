import 'alert_state_machine.dart';

// Decides what the background service does when it detects a fall. Pure Dart
// so the safety rules are unit-tested; services/background_service.dart only
// connects it to Android.
//
// The rules:
//  - If the app is on screen, hand the fall to the app (it runs the normal
//    countdown with voice cancel). "On screen" means a heartbeat arrived
//    recently. A stale heartbeat never counts, so a killed app cannot swallow
//    a fall.
//  - Otherwise the service runs the countdown itself and sends the alert SMS
//    when it expires, because the person may be unconscious with the phone in
//    a pocket and nobody opens the app.
//  - When the app opens during a background countdown or alert, it takes over
//    with the original timing. The service stops so nothing is sent twice.

/// How recent the app's heartbeat must be to count as "on screen".
const appHeartbeatTimeout = Duration(seconds: 10);

class BackgroundCoordinator {
  BackgroundCoordinator({
    required this.machine,
    required this.onCountdown,
    required this.onSendAlert,
    required this.onForwardToApp,
    required this.onClear,
    Clock? clock,
  }) : _clock = clock ?? DateTime.now {
    machine.subscribe(_onAlert);
  }

  final AlertStateMachine machine;
  final Clock _clock;

  /// Show/refresh the "alert sends in N s" notification.
  final void Function(int remaining) onCountdown;

  /// The countdown ran out with nobody cancelling: send the SMS and start
  /// bystander instructions.
  final void Function(AlertSnapshot snapshot) onSendAlert;

  /// The app is on screen; let it handle the fall.
  final void Function() onForwardToApp;

  /// Remove countdown/alert notifications and stop speaking.
  final void Function() onClear;

  DateTime? _lastHeartbeat;

  bool get appOnScreen =>
      _lastHeartbeat != null && _clock().difference(_lastHeartbeat!) < appHeartbeatTimeout;

  void appHeartbeat() => _lastHeartbeat = _clock();
  void appHidden() => _lastHeartbeat = null;

  void fall() {
    if (appOnScreen) {
      onForwardToApp();
    } else {
      machine.trigger(TriggerSource.fall);
    }
  }

  /// Power pressed three times: the person asked for help with the phone
  /// locked, so the service runs the countdown itself (the app takes over if
  /// it is opened).
  void manualTrigger() => machine.trigger(TriggerSource.manual);

  void tick() => machine.tick();

  /// Cancels a background countdown (e.g. "I'm okay" from the notification).
  void cancel() => machine.cancel('tap');

  /// The app is taking over. Returns what it needs to continue the alert with
  /// the same timing, or null when there is nothing in progress.
  Map<String, Object?>? handOver() {
    final s = machine.snapshot();
    if (s.state != AlertState.countdown && s.state != AlertState.active) return null;
    final state = {
      'source': s.source!.name,
      'triggeredAt': s.triggeredAt!.millisecondsSinceEpoch,
      if (s.activatedAt != null) 'activatedAt': s.activatedAt!.millisecondsSinceEpoch,
    };
    machine.reset();
    onClear();
    return state;
  }

  void _onAlert(AlertSnapshot s) {
    switch (s.event) {
      case AlertEvent.triggered:
      case AlertEvent.countdown:
        onCountdown(s.remaining);
      case AlertEvent.activated:
        onSendAlert(s);
      case AlertEvent.cancelled:
      case AlertEvent.resolved:
        onClear();
        machine.reset();
      case AlertEvent.tick:
      case AlertEvent.reset:
        break;
    }
  }
}

/// Rebuilds the arguments for [AlertStateMachine.restore] from [BackgroundCoordinator.handOver].
({TriggerSource source, DateTime triggeredAt, DateTime? activatedAt})? parseHandOver(Map<Object?, Object?>? m) {
  if (m == null || m['source'] == null || m['triggeredAt'] == null) return null;
  final source = TriggerSource.values.asNameMap()[m['source']];
  if (source == null) return null;
  final activated = m['activatedAt'] as num?;
  return (
    source: source,
    triggeredAt: DateTime.fromMillisecondsSinceEpoch((m['triggeredAt'] as num).toInt()),
    activatedAt: activated == null ? null : DateTime.fromMillisecondsSinceEpoch(activated.toInt()),
  );
}
