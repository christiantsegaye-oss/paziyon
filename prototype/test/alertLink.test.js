import { test } from 'node:test';
import assert from 'node:assert/strict';
import { encodeAlert, decodeAlert, smsBody, mapLink } from '../js/core/alertLink.js';

const alert = {
  status: 'active',
  trigger: 'voice',
  time: Date.UTC(2026, 8, 25, 9, 30),
  lat: 9.0301,
  lng: 38.7408,
  profile: { name: 'አበበ ከበደ', condition: 'Epilepsy', medications: 'Carbamazepine', allergies: '' },
};

test('alert round-trips through the link fragment, including Ge’ez text', () => {
  const decoded = decodeAlert('#' + encodeAlert(alert));
  assert.equal(decoded.profile.name, 'አበበ ከበደ');
  assert.equal(decoded.lat, 9.0301);
  assert.equal(decoded.trigger, 'voice');
});

test('the fragment is URL-safe', () => {
  assert.match(encodeAlert(alert), /^[A-Za-z0-9_-]+$/);
});

test('a malformed fragment decodes to null', () => {
  assert.equal(decodeAlert('#not-valid'), null);
});

test('SMS body follows the spec format and handles a missing GPS fix', () => {
  const body = smsBody(alert, 'https://example.test/d');
  assert.match(body, /^\[EMERGENCY\] አበበ ከበደ may be having a seizure\/fall event\. Location: https:\/\/www\.openstreetmap\.org/);
  assert.match(smsBody({ ...alert, lat: null, lng: null }, 'x'), /Location: unknown \(no GPS fix\)/);
  assert.match(smsBody({ ...alert, status: 'resolved' }, 'x'), /has marked themselves as okay/);
  assert.equal(mapLink(null, 1), null);
});
