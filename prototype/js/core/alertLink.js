// The alert SMS carries a link to the caregiver dashboard. With no backend in
// the demo, the alert details travel in the link's #fragment (never sent to a
// server). The real app will point the link at a live alert record instead.

const toBase64Url = (str) => {
  const bytes = new TextEncoder().encode(str);
  let bin = '';
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

const fromBase64Url = (b64) => {
  const bin = atob(b64.replace(/-/g, '+').replace(/_/g, '/'));
  return new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
};

// alert: { status, trigger, time, lat, lng, profile: { name, condition, seizureType, medications, allergies, bloodType } }
export function encodeAlert(alert) {
  const p = alert.profile ?? {};
  const compact = {
    s: alert.status,
    g: alert.trigger,
    t: alert.time,
    la: alert.lat,
    ln: alert.lng,
    n: p.name,
    c: p.condition,
    st: p.seizureType,
    m: p.medications,
    a: p.allergies,
    b: p.bloodType,
  };
  return toBase64Url(JSON.stringify(compact));
}

export function decodeAlert(fragment) {
  try {
    const c = JSON.parse(fromBase64Url(fragment.replace(/^#/, '')));
    return {
      status: c.s,
      trigger: c.g,
      time: c.t,
      lat: c.la,
      lng: c.ln,
      profile: {
        name: c.n,
        condition: c.c,
        seizureType: c.st,
        medications: c.m,
        allergies: c.a,
        bloodType: c.b,
      },
    };
  } catch {
    return null;
  }
}

export const mapLink = (lat, lng) =>
  lat == null || lng == null ? null : `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=17/${lat}/${lng}`;

// Message formats from spec section 4.3 (Screen C) and 6.2 step 4.
export function smsBody(alert, dashboardUrl, appName = 'P.A.Z.I.Y.O.N') {
  const name = alert.profile?.name || 'Your contact';
  if (alert.status === 'resolved') {
    return `${name} has marked themselves as okay. Alert resolved. ${dashboardUrl}`;
  }
  const where = mapLink(alert.lat, alert.lng) ?? 'unknown (no GPS fix)';
  const when = new Date(alert.time).toLocaleString();
  return `[EMERGENCY] ${name} may be having a seizure/fall event. Location: ${where}. Time: ${when}. Details: ${dashboardUrl} This is an automated alert from ${appName}. Please check on them or call emergency services.`;
}
