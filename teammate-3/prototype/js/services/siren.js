// A loud siren between spoken instructions, to draw people over. The browser
// cannot raise the system volume, so the page plays it at full page volume.

let audio = null;
let timer = null;
let finish = null;

export const sirenPlaying = () => Boolean(finish);

/** Plays the siren for `ms`; resolves when it stops (or is stopped). */
export function sirenBurst(ms) {
  stopSiren();
  audio ??= Object.assign(new Audio('audio/siren.wav'), { loop: true, volume: 1 });
  audio.currentTime = 0;
  audio.play().catch(() => {});
  return new Promise((resolve) => {
    finish = () => {
      clearTimeout(timer);
      audio.pause();
      finish = null;
      resolve();
    };
    timer = setTimeout(finish, ms);
  });
}

export function stopSiren() {
  finish?.();
}
