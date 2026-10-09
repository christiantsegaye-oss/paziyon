import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createFallDetector } from '../js/core/fallDetector.js';

const HZ = 50;
const STEP = 1000 / HZ;

// Builds a stream of { t, x, y, z } samples from segments of [durationMs, magnitudeFn].
function stream(segments) {
  const out = [];
  let t = 0;
  for (const [ms, mag] of segments) {
    for (let e = 0; e < ms; e += STEP) {
      out.push({ t, x: 0, y: 0, z: mag(t, e) });
      t += STEP;
    }
  }
  return out;
}

const rest = () => 9.8 + (Math.random() - 0.5) * 0.2;
const freefall = () => 1;
const impact = () => 32;
const walking = (t) => 9.8 + 4 * Math.sin(t / 80);

function run(samples, sensitivity = 'medium') {
  const falls = [];
  const detector = createFallDetector({ sensitivity, onFall: (e) => falls.push(e) });
  samples.forEach((s) => detector.push(s));
  return falls;
}

test('freefall, impact, then stillness is a fall', () => {
  const falls = run(stream([[1000, rest], [300, freefall], [40, impact], [4000, rest]]));
  assert.equal(falls.length, 1);
});

test('a dropped phone that is picked up and carried is not a fall', () => {
  const falls = run(stream([[1000, rest], [300, freefall], [40, impact], [4000, walking]]));
  assert.equal(falls.length, 0);
});

test('an impact without a freefall is not a fall', () => {
  const falls = run(stream([[1000, rest], [40, impact], [4000, rest]]));
  assert.equal(falls.length, 0);
});

test('a freefall too short for the threshold is ignored', () => {
  const falls = run(stream([[1000, rest], [100, freefall], [40, impact], [4000, rest]]));
  assert.equal(falls.length, 0);
});

test('an impact more than 1 s after the freefall is ignored', () => {
  const falls = run(stream([[1000, rest], [300, freefall], [1500, rest], [40, impact], [4000, rest]]));
  assert.equal(falls.length, 0);
});

test('high sensitivity catches a softer impact that medium misses', () => {
  const soft = () => 22;
  const samples = stream([[1000, rest], [300, freefall], [40, soft], [4000, rest]]);
  assert.equal(run(samples, 'medium').length, 0);
  assert.equal(run(samples, 'high').length, 1);
});

test('a short bounce right after impact does not break the stillness check', () => {
  const bounce = () => 17;
  const falls = run(stream([[1000, rest], [300, freefall], [40, impact], [400, bounce], [4000, rest]]));
  assert.equal(falls.length, 1);
});
