// Rule-based fall detection (spec section 5.3):
//   1. freefall  — acceleration magnitude below a threshold for a minimum time
//   2. impact    — a spike above a threshold within 1 s of the freefall
//   3. stillness — low magnitude variance for a window after the impact
// A phone that is picked up or carried after the impact is a drop, not a fall.
// All thresholds are starting points to be tuned on real phones.

// "high" fires more easily: a looser freefall threshold, a lower impact spike,
// a shorter stillness window and more tolerated movement.
export const SENSITIVITY = Object.freeze({
  low: { freefall: 2.5, freefallMs: 250, impact: 28, stillMs: 4000, stillVariance: 0.5 },
  medium: { freefall: 3, freefallMs: 200, impact: 25, stillMs: 3000, stillVariance: 1 },
  high: { freefall: 3.5, freefallMs: 150, impact: 20, stillMs: 2000, stillVariance: 2 },
});

const IMPACT_WINDOW_MS = 1000;
// Ignore the bounce right after impact when measuring stillness.
const SETTLE_MS = 500;

export const magnitude = ({ x, y, z }) => Math.sqrt(x * x + y * y + z * z);

function variance(values) {
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  return values.reduce((a, v) => a + (v - mean) ** 2, 0) / values.length;
}

export function createFallDetector({ sensitivity = 'medium', onFall = () => {}, onStage = () => {} } = {}) {
  let cfg = SENSITIVITY[sensitivity] ?? SENSITIVITY.medium;
  let stage, freefallStart, impactDeadline, impactAt, stillSamples;

  const setStage = (next, t) => {
    stage = next;
    onStage(next, t);
  };
  const reset = () => {
    stage = 'monitor';
    freefallStart = null;
    impactDeadline = null;
    impactAt = null;
    stillSamples = [];
  };
  reset();

  return {
    get stage() {
      return stage;
    },
    setSensitivity(level) {
      cfg = SENSITIVITY[level] ?? SENSITIVITY.medium;
    },
    reset,
    // sample: { t: ms timestamp, x, y, z: m/s² including gravity }
    push(sample) {
      const { t } = sample;
      const mag = magnitude(sample);

      if (stage === 'monitor') {
        if (mag < cfg.freefall) {
          freefallStart ??= t;
          if (t - freefallStart >= cfg.freefallMs) {
            impactDeadline = t + IMPACT_WINDOW_MS;
            setStage('freefall', t);
          }
        } else {
          freefallStart = null;
        }
      } else if (stage === 'freefall') {
        if (mag > cfg.impact) {
          impactAt = t;
          stillSamples = [];
          setStage('impact', t);
        } else if (t > impactDeadline) {
          reset();
          setStage('monitor', t);
        }
      } else if (stage === 'impact') {
        if (t - impactAt < SETTLE_MS) return;
        stillSamples.push(mag);
        if (t - impactAt >= SETTLE_MS + cfg.stillMs) {
          const still = variance(stillSamples) < cfg.stillVariance;
          reset();
          setStage('monitor', t);
          if (still) onFall({ at: t });
        }
      }
    },
  };
}
