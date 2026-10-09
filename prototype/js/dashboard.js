import { decodeAlert, mapLink } from './core/alertLink.js';
import { EMERGENCY_NUMBER } from './core/content.js';

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const TRIGGERS = { voice: 'voice command', manual: 'manual button', fall: 'automatic fall detection' };
const root = document.getElementById('content');

function render() {
  const alert = decodeAlert(location.hash);
  if (!alert) {
    root.innerHTML = `<h1>No alert</h1><p class="muted">Open this page from the link in an alert SMS.</p>`;
    return;
  }
  const p = alert.profile;
  const name = esc(p.name || 'Your contact');
  const active = alert.status !== 'resolved';
  const when = new Date(alert.time);
  const hasFix = alert.lat != null && alert.lng != null;
  const d = 0.004;
  const embed = hasFix
    ? `https://www.openstreetmap.org/export/embed.html?bbox=${alert.lng - d},${alert.lat - d},${alert.lng + d},${alert.lat + d}&layer=mapnik&marker=${alert.lat},${alert.lng}`
    : null;

  document.title = active ? `Emergency: ${p.name || 'Alert'} · P.A.Z.I.Y.O.N` : `Resolved: ${p.name || 'Alert'} · P.A.Z.I.Y.O.N`;
  root.innerHTML = `
    <div class="banner ${active ? 'banner--active' : 'banner--resolved'}" role="status">
      ${active ? `${name} may be having a seizure or fall` : `${name} has marked themselves as okay`}
      <small>${active ? 'Alert sent' : 'Alert resolved'} ${esc(when.toLocaleString())} · triggered by ${esc(TRIGGERS[alert.trigger] ?? alert.trigger)}</small>
    </div>
    ${active ? `<a class="btn btn--call" href="tel:${EMERGENCY_NUMBER}">Call emergency services · ${EMERGENCY_NUMBER}</a>` : ''}
    <h2>Location</h2>
    ${
      hasFix
        ? `<iframe class="map" title="Map of ${name}'s location" src="${embed}" loading="lazy"></iframe>
           <a class="btn" href="${mapLink(alert.lat, alert.lng)}" target="_blank" rel="noopener">Open in maps ↗</a>
           <p class="muted">${alert.lat}, ${alert.lng}</p>`
        : `<p class="muted">The phone had no GPS fix when the alert was sent.</p>`
    }
    <h2>Medical ID</h2>
    <div class="medical"><h3>MEDICAL ID</h3><dl>
      ${[['Name', p.name], ['Condition', p.condition], ['Seizure type', p.seizureType], ['Medications', p.medications], ['Allergies', p.allergies], ['Blood type', p.bloodType]]
        .filter(([, v]) => v)
        .map(([k, v]) => `<dt>${k}</dt><dd>${esc(v)}</dd>`)
        .join('')}
    </dl></div>
    <h2>What to do</h2>
    <ul>
      <li>Call or go to them. If someone is with them, the phone is speaking first-aid steps.</li>
      <li>If the seizure lasts more than 5 minutes, call emergency services.</li>
    </ul>`;
}

render();
addEventListener('hashchange', render);
