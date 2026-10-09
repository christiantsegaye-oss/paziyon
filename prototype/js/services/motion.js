// Feeds accelerometer samples to the fall detector. On a phone this uses the
// real sensor; on a laptop, simulateFall() plays a recorded-style sample stream
// through the same detector.

let handler = null;

export async function startMotion(onSample) {
  stopMotion();
  const DME = globalThis.DeviceMotionEvent;
  if (!DME) return 'unsupported';
  // iOS requires an explicit permission request from a user gesture.
  if (typeof DME.requestPermission === 'function') {
    try {
      if ((await DME.requestPermission()) !== 'granted') return 'denied';
    } catch {
      return 'denied';
    }
  }
  handler = (e) => {
    const a = e.accelerationIncludingGravity;
    if (a?.x == null) return;
    onSample({ t: performance.now(), x: a.x, y: a.y, z: a.z });
  };
  addEventListener('devicemotion', handler);
  return 'on';
}

export function stopMotion() {
  if (handler) removeEventListener('devicemotion', handler);
  handler = null;
}

// Freefall → impact → stillness, pushed at 50 Hz in real time.
export function simulateFall(onSample, onDone = () => {}) {
  const segments = [
    [500, () => 9.8],
    [350, () => 0.8],
    [60, () => 34],
    [250, () => 14 + Math.random() * 6],
    [3600, () => 9.8 + (Math.random() - 0.5) * 0.15],
  ];
  const samples = [];
  let t = performance.now();
  for (const [ms, mag] of segments) {
    for (let e = 0; e < ms; e += 20) samples.push({ t: (t += 20), x: 0, y: 0, z: mag() });
  }
  const start = performance.now();
  const first = samples[0].t;
  let i = 0;
  const timer = setInterval(() => {
    const now = performance.now() - start + first;
    while (i < samples.length && samples[i].t <= now) onSample(samples[i++]);
    if (i >= samples.length) {
      clearInterval(timer);
      onDone();
    }
  }, 20);
}
