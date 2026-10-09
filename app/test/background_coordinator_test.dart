import 'package:flutter_test/flutter_test.dart';
import 'package:seizure_alert/core/alert_state_machine.dart';
import 'package:seizure_alert/core/background_coordinator.dart';

void main() {
  late DateTime now;
  late BackgroundCoordinator bg;
  late List<String> log;

  setUp(() {
    now = DateTime(2026, 9, 25, 9);
    log = [];
    bg = BackgroundCoordinator(
      machine: AlertStateMachine(cancelWindowSeconds: 15, clock: () => now),
      clock: () => now,
      onCountdown: (n) => log.add('countdown $n'),
      onSendAlert: (_) => log.add('send'),
      onForwardToApp: () => log.add('forward'),
      onClear: () => log.add('clear'),
    );
  });

  void advance(int seconds) {
    for (var i = 0; i < seconds * 4; i++) {
      now = now.add(const Duration(milliseconds: 250));
      bg.tick();
    }
  }

  test('with the app on screen, a fall is handed to the app', () {
    bg.appHeartbeat();
    bg.fall();
    expect(log, ['forward']);
    expect(bg.machine.state, AlertState.idle);
  });

  test('with no app on screen, the service counts down and sends the alert itself', () {
    bg.fall();
    expect(log.first, 'countdown 15');
    advance(16);
    expect(log.last, 'send');
    expect(log.where((l) => l == 'send'), hasLength(1));
    expect(bg.machine.state, AlertState.active);
  });

  test('a stale heartbeat does not count: a killed app cannot swallow a fall', () {
    bg.appHeartbeat();
    advance(11);
    bg.fall();
    expect(log, isNot(contains('forward')));
    expect(bg.machine.state, AlertState.countdown);
  });

  test('the app going to the background stops falls being forwarded', () {
    bg.appHeartbeat();
    bg.appHidden();
    bg.fall();
    expect(bg.machine.state, AlertState.countdown);
  });

  test('cancelling the background countdown clears it and sends nothing', () {
    bg.fall();
    advance(5);
    bg.cancel();
    advance(20);
    expect(log, isNot(contains('send')));
    expect(log.last, 'clear');
    expect(bg.machine.state, AlertState.idle);
  });

  test('the app takes over a countdown with its original timing and nothing is sent twice', () {
    bg.fall();
    final triggeredAt = now;
    advance(6);
    final handed = parseHandOver(bg.handOver())!;
    expect(handed.source, TriggerSource.fall);
    expect(handed.triggeredAt, triggeredAt);
    expect(handed.activatedAt, isNull);
    advance(20);
    expect(log, isNot(contains('send')));

    // The app continues the same countdown: 9 seconds left, not 15.
    final app = AlertStateMachine(cancelWindowSeconds: 15, clock: () => now.subtract(const Duration(seconds: 20)));
    app.restore(source: handed.source, triggeredAt: handed.triggeredAt);
    expect(app.state, AlertState.countdown);
    expect(app.remaining, 9);
  });

  test('the app takes over an alert that was already sent', () {
    bg.fall();
    advance(16);
    final handed = parseHandOver(bg.handOver())!;
    expect(handed.activatedAt, isNotNull);
    final app = AlertStateMachine(clock: () => now);
    app.restore(source: handed.source, triggeredAt: handed.triggeredAt, activatedAt: handed.activatedAt);
    expect(app.state, AlertState.active);
    expect(app.elapsed, 1);
  });

  test('nothing to hand over when idle', () {
    expect(bg.handOver(), isNull);
    expect(parseHandOver(null), isNull);
  });

  test('three power presses start the countdown in the service, even with the app open', () {
    bg.appHeartbeat();
    bg.manualTrigger();
    expect(bg.machine.state, AlertState.countdown);
    expect(bg.machine.snapshot().source, TriggerSource.manual);
    advance(16);
    expect(log.last, 'send');
  });
}
