// Alert lifecycle: idle → countdown → active → resolved.
// Time only moves forward through tick(), so the UI drives it with a timer
// and tests drive it with a fake clock.

export const STATES = Object.freeze({
  IDLE: 'idle',
  COUNTDOWN: 'countdown',
  ACTIVE: 'active',
  RESOLVED: 'resolved',
});

export function createAlertMachine({ cancelWindowSeconds = 15, clock = () => Date.now() } = {}) {
  let s = { state: STATES.IDLE };
  let lastRemaining = null;
  const listeners = new Set();

  const remaining = () =>
    s.state === STATES.COUNTDOWN ? Math.max(0, Math.ceil((s.deadline - clock()) / 1000)) : 0;
  const elapsed = () =>
    s.state === STATES.ACTIVE ? Math.floor((clock() - s.activatedAt) / 1000) : 0;
  const snapshot = () => ({ ...s, remaining: remaining(), elapsed: elapsed() });
  const emit = (event) => {
    const snap = { ...snapshot(), event };
    listeners.forEach((fn) => fn(snap));
  };
  const finish = (outcome, by) => {
    s = { ...s, state: STATES.RESOLVED, outcome, resolvedBy: by, resolvedAt: clock() };
    emit(outcome);
  };

  return {
    get state() {
      return s.state;
    },
    snapshot,
    subscribe(fn) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    setCancelWindow(seconds) {
      cancelWindowSeconds = seconds;
    },
    // source: 'voice' | 'manual' | 'fall'
    trigger(source) {
      if (s.state !== STATES.IDLE) return false;
      const t = clock();
      s = { state: STATES.COUNTDOWN, source, triggeredAt: t, deadline: t + cancelWindowSeconds * 1000 };
      lastRemaining = remaining();
      emit('triggered');
      return true;
    },
    // by: 'voice' | 'tap'
    cancel(by = 'tap') {
      if (s.state !== STATES.COUNTDOWN) return false;
      finish('cancelled', by);
      return true;
    },
    tick() {
      if (s.state === STATES.COUNTDOWN) {
        if (clock() >= s.deadline) {
          s = { ...s, state: STATES.ACTIVE, activatedAt: clock() };
          emit('activated');
        } else if (remaining() !== lastRemaining) {
          lastRemaining = remaining();
          emit('countdown');
        }
      } else if (s.state === STATES.ACTIVE) {
        emit('tick');
      }
    },
    // Ends an active alert (patient returned / hold-to-confirm).
    resolve(by = 'tap') {
      if (s.state !== STATES.ACTIVE) return false;
      finish('resolved', by);
      return true;
    },
    reset() {
      s = { state: STATES.IDLE };
      emit('reset');
    },
  };
}
