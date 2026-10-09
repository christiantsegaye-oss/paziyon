import 'dart:math' as math;

// Rule-based fall detection (spec section 5.3):
//   1. freefall  — acceleration magnitude below a threshold for a minimum time
//   2. impact    — a spike above a threshold within 1 s of the freefall
//   3. stillness — low magnitude variance for a window after the impact
// A phone that is picked up or carried after the impact is a drop, not a fall.
// Port of prototype/js/core/fallDetector.js; thresholds are starting points to
// be tuned on real phones.

enum Sensitivity { low, medium, high }

enum FallStage { monitor, freefall, impact }

class FallThresholds {
  const FallThresholds({
    required this.freefall,
    required this.freefallMs,
    required this.impact,
    required this.stillMs,
    required this.stillVariance,
  });

  final double freefall;
  final int freefallMs;
  final double impact;
  final int stillMs;
  final double stillVariance;

  // "high" fires more easily: a looser freefall threshold, a lower impact
  // spike, a shorter stillness window and more tolerated movement.
  static const values = {
    Sensitivity.low: FallThresholds(freefall: 2.5, freefallMs: 250, impact: 28, stillMs: 4000, stillVariance: 0.5),
    Sensitivity.medium: FallThresholds(freefall: 3, freefallMs: 200, impact: 25, stillMs: 3000, stillVariance: 1),
    Sensitivity.high: FallThresholds(freefall: 3.5, freefallMs: 150, impact: 20, stillMs: 2000, stillVariance: 2),
  };
}

/// One accelerometer reading including gravity, in m/s². [t] is milliseconds.
class MotionSample {
  const MotionSample(this.t, this.x, this.y, this.z);
  final int t;
  final double x, y, z;

  double get magnitude => math.sqrt(x * x + y * y + z * z);
}

const _impactWindowMs = 1000;
// Ignore the bounce right after impact when measuring stillness.
const _settleMs = 500;

double _variance(List<double> values) {
  final mean = values.reduce((a, b) => a + b) / values.length;
  return values.fold<double>(0, (a, v) => a + (v - mean) * (v - mean)) / values.length;
}

class FallDetector {
  FallDetector({Sensitivity sensitivity = Sensitivity.medium, this.onFall, this.onStage})
      : _cfg = FallThresholds.values[sensitivity]!;

  void Function(int at)? onFall;
  void Function(FallStage stage)? onStage;

  FallThresholds _cfg;
  FallStage _stage = FallStage.monitor;
  int? _freefallStart, _impactDeadline, _impactAt;
  final _stillSamples = <double>[];

  FallStage get stage => _stage;

  set sensitivity(Sensitivity level) => _cfg = FallThresholds.values[level]!;

  void reset() {
    _stage = FallStage.monitor;
    _freefallStart = _impactDeadline = _impactAt = null;
    _stillSamples.clear();
  }

  void _setStage(FallStage next) {
    _stage = next;
    onStage?.call(next);
  }

  void push(MotionSample sample) {
    final t = sample.t;
    final mag = sample.magnitude;

    switch (_stage) {
      case FallStage.monitor:
        if (mag < _cfg.freefall) {
          _freefallStart ??= t;
          if (t - _freefallStart! >= _cfg.freefallMs) {
            _impactDeadline = t + _impactWindowMs;
            _setStage(FallStage.freefall);
          }
        } else {
          _freefallStart = null;
        }
      case FallStage.freefall:
        if (mag > _cfg.impact) {
          _impactAt = t;
          _stillSamples.clear();
          _setStage(FallStage.impact);
        } else if (t > _impactDeadline!) {
          reset();
          _setStage(FallStage.monitor);
        }
      case FallStage.impact:
        if (t - _impactAt! < _settleMs) return;
        _stillSamples.add(mag);
        if (t - _impactAt! >= _settleMs + _cfg.stillMs) {
          final still = _variance(_stillSamples) < _cfg.stillVariance;
          reset();
          _setStage(FallStage.monitor);
          if (still) onFall?.call(t);
        }
    }
  }
}
