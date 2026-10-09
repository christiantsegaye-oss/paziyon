// Everything stays on the device (spec 4.5): profile, contacts, settings, events.

const KEY = 'sfa-demo-v1';

export const DEFAULTS = {
  profile: { name: '', condition: 'Epilepsy', seizureType: 'Tonic-clonic', medications: '', allergies: '', bloodType: '' },
  contacts: [],
  settings: {
    language: 'en',
    languageOrder: ['am', 'om', 'en'],
    cancelWindowSeconds: 15,
    fallDetection: true,
    sensitivity: 'medium',
    voiceTrigger: true,
    voxideKey: '',
    voxideAlwaysListen: true,
    siren: true,
  },
  events: [],
};

export function load() {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) ?? 'null');
    if (!saved) return structuredClone(DEFAULTS);
    return {
      profile: { ...DEFAULTS.profile, ...saved.profile },
      contacts: saved.contacts ?? [],
      settings: { ...DEFAULTS.settings, ...saved.settings },
      events: saved.events ?? [],
    };
  } catch {
    return structuredClone(DEFAULTS);
  }
}

export function save(data) {
  try {
    localStorage.setItem(KEY, JSON.stringify(data));
  } catch {
    // Private mode or storage blocked: the demo still runs, it just won't persist.
  }
}

export function clear() {
  try {
    localStorage.removeItem(KEY);
  } catch {}
}
