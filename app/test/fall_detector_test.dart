import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:seizure_alert/core/fall_detector.dart';

const _stepMs = 20; // 50 Hz

typedef Mag = double Function(int t);

/// Builds samples from segments of (durationMs, magnitude function).
List<MotionSample> stream(List<(int, Mag)> segments) {
  final out = <MotionSample>[];
  var t = 0;
  for (final (ms, mag) in segments) {
    for (var e = 0; e < ms; e += _stepMs) {
      out.add(MotionSample(t, 0, 0, mag(t)));
      t += _stepMs;
    }
  }
  return out;
}

final _rng = Random(7);
double rest(int _) => 9.8 + (_rng.nextDouble() - 0.5) * 0.2;
double freefall(int _) => 1;
double impact(int _) => 32;
double walking(int t) => 9.8 + 4 * sin(t / 80);

int run(List<MotionSample> samples, [Sensitivity s = Sensitivity.medium]) {
  var falls = 0;
  final detector = FallDetector(sensitivity: s, onFall: (_) => falls++);
  samples.forEach(detector.push);
  return falls;
}

void main() {
  test('freefall, impact, then stillness is a fall', () {
    expect(run(stream([(1000, rest), (300, freefall), (40, impact), (4000, rest)])), 1);
  });

  test('a dropped phone that is picked up and carried is not a fall', () {
    expect(run(stream([(1000, rest), (300, freefall), (40, impact), (4000, walking)])), 0);
  });

  test('an impact without a freefall is not a fall', () {
    expect(run(stream([(1000, rest), (40, impact), (4000, rest)])), 0);
  });

  test('a freefall too short for the threshold is ignored', () {
    expect(run(stream([(1000, rest), (100, freefall), (40, impact), (4000, rest)])), 0);
  });

  test('an impact more than 1 s after the freefall is ignored', () {
    expect(run(stream([(1000, rest), (300, freefall), (1500, rest), (40, impact), (4000, rest)])), 0);
  });

  test('high sensitivity catches a softer impact that medium misses', () {
    final samples = stream([(1000, rest), (300, freefall), (40, (_) => 22), (4000, rest)]);
    expect(run(samples, Sensitivity.medium), 0);
    expect(run(samples, Sensitivity.high), 1);
  });

  test('a short bounce right after impact does not break the stillness check', () {
    expect(run(stream([(1000, rest), (300, freefall), (40, impact), (400, (_) => 17), (4000, rest)])), 1);
  });
}
