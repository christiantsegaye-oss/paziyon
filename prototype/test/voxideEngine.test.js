import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ENGINE = readFileSync(new URL('../../app/assets/voxide/paziyon-voxide.js', import.meta.url), 'utf8');

// Minimal stand-in for the Voxide SDK with the same surface the engine uses.
function fakeVoxide() {
  const clients = [];
  class VoxideClient {
    constructor(config) {
      this.config = config;
      this.listeners = {};
      this.subs = [];
      this.snapshot = { messages: [] };
      this.sent = [];
      this.connects = 0;
      clients.push(this);
    }
    enableMultilingual(o) { this.multi = o; return this; }
    bindState(fn) { this.stateFn = fn; return this; }
    register(actions) { this.actions = actions; return this; }
    on(e, cb) { (this.listeners[e] ||= []).push(cb); return () => {}; }
    emit(e, p) { (this.listeners[e] || []).forEach((cb) => cb(p)); }
    subscribe(cb) { this.subs.push(cb); return () => {}; }
    getSnapshot() { return this.snapshot; }
    setLanguage(l) { this.lang = l; return this; }
    async init() { return this; }
    async connect() { this.connects++; this.emit('status', 'listening'); }
    disconnect() { this.emit('status', 'idle'); }
    async sendText(t) { this.sent.push(t); }
    interrupt() {}
    getInputLevel() { return 0; }
  }
  return { VoxideClient, clients };
}

// Values from inside the vm sandbox have that realm's prototypes.
const plain = (v) => JSON.parse(JSON.stringify(v));

function load() {
  const Voxide = fakeVoxide();
  const ctx = { window: {}, setTimeout, clearTimeout, Promise };
  ctx.window.Voxide = Voxide;
  vm.runInNewContext(ENGINE, ctx);
  return { PaziyonVoxide: ctx.window.PaziyonVoxide, clients: Voxide.clients };
}

test('registers every P.A.Z.I.Y.O.N capability and sends app instructions each turn', () => {
  const { PaziyonVoxide, clients } = load();
  PaziyonVoxide.create({ key: 'vox_pub_test', language: 'am', onEvent() {} });
  const c = clients[0];
  assert.deepEqual(Object.keys(c.actions).sort(), [
    'call_emergency_services', 'cancel_alert', 'get_alert_status', 'get_first_aid_step', 'get_medical_info', 'start_emergency_alert',
  ]);
  assert.equal(c.config.language, 'am-ET');
  assert.deepEqual(plain(c.multi.supported), ['am-ET', 'om-ET', 'en-US']);
  assert.match(c.stateFn().instructions, /Amharic, Afaan Oromo or English/);
});

test('a capability call reaches the app and its answer goes back to the agent', async () => {
  const { PaziyonVoxide, clients } = load();
  const events = [];
  const engine = PaziyonVoxide.create({ key: 'vox_pub_test', onEvent: (e) => events.push(e) });
  const result = clients[0].actions.get_alert_status.handler({});
  const call = events.find((e) => e.type === 'tool');
  assert.equal(call.name, 'get_alert_status');
  engine.resolveTool(call.id, { elapsedSeconds: 42 });
  assert.deepEqual(plain(await result), { elapsedSeconds: 42 });
});

test('live speech is reported as it is heard, then as final', () => {
  const { PaziyonVoxide, clients } = load();
  const events = [];
  PaziyonVoxide.create({ key: 'vox_pub_test', onEvent: (e) => events.push(e) });
  const c = clients[0];
  c.snapshot = { messages: [{ role: 'user', text: 'እርዳ', partial: true }] };
  c.subs.forEach((s) => s());
  c.emit('message', { role: 'user', text: 'እርዳታ' });
  assert.deepEqual(plain(events.filter((e) => e.type === 'heard')), [
    { type: 'heard', text: 'እርዳ', final: false },
    { type: 'heard', text: 'እርዳታ', final: true },
  ]);
});

test('say() asks the agent to read the text in the right language and waits until it has spoken', async () => {
  const { PaziyonVoxide, clients } = load();
  const engine = PaziyonVoxide.create({ key: 'vox_pub_test', onEvent() {} });
  await engine.start();
  const c = clients[0];
  let done = false;
  const p = engine.say('ይህ ሰው የሚጥል ሕመም...', 'am').then(() => (done = true));
  await new Promise((r) => setTimeout(r, 5));
  assert.match(c.sent[0], /in Amharic/);
  assert.match(c.sent[0], /ይህ ሰው የሚጥል ሕመም/);
  c.emit('status', 'speaking');
  await new Promise((r) => setTimeout(r, 5));
  assert.equal(done, false, 'still speaking');
  c.emit('status', 'listening');
  await p;
  assert.equal(done, true);
});

test('say() does nothing when not connected, so the app falls back to its own audio', async () => {
  const { PaziyonVoxide } = load();
  const engine = PaziyonVoxide.create({ key: 'vox_pub_test', onEvent() {} });
  assert.equal(await engine.say('hello', 'en'), false);
});

test('a dropped session reconnects while listening is wanted, but not after stop()', async () => {
  const { PaziyonVoxide, clients } = load();
  const engine = PaziyonVoxide.create({ key: 'vox_pub_test', onEvent() {} });
  await engine.start();
  const c = clients[0];
  c.emit('status', 'idle'); // e.g. session time limit
  await new Promise((r) => setTimeout(r, 2100));
  assert.equal(c.connects, 2);
  engine.stop();
  await new Promise((r) => setTimeout(r, 2100));
  assert.equal(c.connects, 2);
});

test('running out of Voxide sessions stops retrying and says why', async () => {
  const { PaziyonVoxide, clients } = load();
  const events = [];
  const engine = PaziyonVoxide.create({ key: 'vox_pub_test', onEvent: (e) => events.push(e) });
  await engine.start();
  clients[0].emit('error', 'usage_limit');
  assert.equal(engine.stopReason, 'usage_limit');
  assert.match(events.find((e) => e.type === 'error').message, /run out of voice sessions/);
});

test('the web demo and the app ship the same Voxide files', () => {
  for (const name of ['paziyon-voxide.js', 'voxide.browser.js', 'VOXIDE_LICENSE']) {
    const app = readFileSync(new URL(`../../app/assets/voxide/${name}`, import.meta.url), 'utf8');
    const web = readFileSync(new URL(`../vendor/${name}`, import.meta.url), 'utf8');
    assert.equal(web, app, `${name} differs: copy app/assets/voxide/${name} to prototype/vendor/`);
  }
});
