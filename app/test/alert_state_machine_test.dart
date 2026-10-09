import 'package:flutter_test/flutter_test.dart';
import 'package:seizure_alert/core/alert_state_machine.dart';

void main() {
  late DateTime now;
  late AlertStateMachine machine;
  late List<AlertEvent> events;

  void setUpMachine([int window = 15]) {
    now = DateTime(2026, 9, 25, 9);
    machine = AlertStateMachine(cancelWindowSeconds: window, clock: () => now);
    events = [];
    machine.subscribe((s) => events.add(s.event));
  }

  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  test('trigger starts a countdown with the full cancel window', () {
    setUpMachine();
    expect(machine.trigger(TriggerSource.voice), isTrue);
    expect(machine.state, AlertState.countdown);
    expect(machine.remaining, 15);
    expect(machine.snapshot().source, TriggerSource.voice);
  });

  test('a second trigger while not idle is ignored', () {
    setUpMachine();
    machine.trigger(TriggerSource.manual);
    expect(machine.trigger(TriggerSource.fall), isFalse);
    expect(machine.snapshot().source, TriggerSource.manual);
  });

  test('countdown emits once per second and activates at zero', () {
    setUpMachine(3);
    machine.trigger(TriggerSource.manual);
    for (var i = 0; i < 12; i++) {
      advance(250);
      machine.tick();
    }
    expect(machine.state, AlertState.active);
    expect(events, [AlertEvent.triggered, AlertEvent.countdown, AlertEvent.countdown, AlertEvent.activated]);
  });

  test('cancel during countdown resolves as cancelled', () {
    setUpMachine();
    machine.trigger(TriggerSource.fall);
    advance(5000);
    expect(machine.cancel('voice'), isTrue);
    final snap = machine.snapshot();
    expect(snap.state, AlertState.resolved);
    expect(snap.outcome, AlertOutcome.cancelled);
    expect(snap.resolvedBy, 'voice');
  });

  test('cancel does nothing once the alert is active', () {
    setUpMachine(1);
    machine.trigger(TriggerSource.manual);
    advance(1000);
    machine.tick();
    expect(machine.cancel(), isFalse);
    expect(machine.state, AlertState.active);
  });

  test('elapsed time counts from activation and resolve ends the alert', () {
    setUpMachine(1);
    machine.trigger(TriggerSource.manual);
    advance(1000);
    machine.tick();
    advance(65400);
    expect(machine.elapsed, 65);
    expect(machine.resolve(), isTrue);
    expect(machine.snapshot().outcome, AlertOutcome.resolved);
    machine.reset();
    expect(machine.state, AlertState.idle);
  });
}
