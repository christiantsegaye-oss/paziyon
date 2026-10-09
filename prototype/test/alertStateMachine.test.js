import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAlertMachine, STATES } from '../js/core/alertStateMachine.js';

function setup(cancelWindowSeconds = 15) {
  let now = 1_000_000;
  const clock = () => now;
  const machine = createAlertMachine({ cancelWindowSeconds, clock });
  const events = [];
  machine.subscribe((snap) => events.push(snap.event));
  return { machine, events, advance: (ms) => (now += ms) };
}

test('trigger starts a countdown with the full cancel window', () => {
  const { machine } = setup(15);
  assert.equal(machine.trigger('voice'), true);
  assert.equal(machine.state, STATES.COUNTDOWN);
  assert.equal(machine.snapshot().remaining, 15);
  assert.equal(machine.snapshot().source, 'voice');
});

test('a second trigger while not idle is ignored', () => {
  const { machine } = setup();
  machine.trigger('manual');
  assert.equal(machine.trigger('fall'), false);
  assert.equal(machine.snapshot().source, 'manual');
});

test('countdown emits once per second and activates at zero', () => {
  const { machine, events, advance } = setup(3);
  machine.trigger('manual');
  for (let i = 0; i < 12; i++) {
    advance(250);
    machine.tick();
  }
  assert.equal(machine.state, STATES.ACTIVE);
  assert.deepEqual(events, ['triggered', 'countdown', 'countdown', 'activated']);
});

test('cancel during countdown resolves as cancelled', () => {
  const { machine, advance } = setup();
  machine.trigger('fall');
  advance(5000);
  assert.equal(machine.cancel('voice'), true);
  const snap = machine.snapshot();
  assert.equal(snap.state, STATES.RESOLVED);
  assert.equal(snap.outcome, 'cancelled');
  assert.equal(snap.resolvedBy, 'voice');
});

test('cancel does nothing once the alert is active', () => {
  const { machine, advance } = setup(1);
  machine.trigger('manual');
  advance(1000);
  machine.tick();
  assert.equal(machine.cancel(), false);
  assert.equal(machine.state, STATES.ACTIVE);
});

test('elapsed time counts from activation and resolve ends the alert', () => {
  const { machine, advance } = setup(1);
  machine.trigger('manual');
  advance(1000);
  machine.tick();
  advance(65_400);
  assert.equal(machine.snapshot().elapsed, 65);
  assert.equal(machine.resolve('tap'), true);
  assert.equal(machine.snapshot().outcome, 'resolved');
  machine.reset();
  assert.equal(machine.state, STATES.IDLE);
});
