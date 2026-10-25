// Inloglimiet per IP + e-mailadres (src/login_limit.js, migratie 0005): één persoon op een gedeeld netwerk sluit de
// anderen niet buiten; dezelfde combinatie krijgt hoogstens 10 mislukte pogingen (of verstuurde codes) per minuut.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { d1 } from './d1.mjs';

const { loginGate, loginKey } = await import('../src/login_limit.js');
const { cleanup } = await import('../src/cron.js');

const T = Date.parse('2026-10-26T10:00:05.000Z');
const SIGN_IN = '/auth/sign-in/email';
const req = (email, path = SIGN_IN) =>
  new Request(`https://api.test${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password: 'x' }) });
/** Een poging: geweigerd door de limiet (true), of doorgelaten met uitkomst [ok]. */
async function attempt(db, email, ok, { ip = '1.2.3.4', path = SIGN_IN, now = T } = {}) {
  const g = await loginGate(db, req(email, path), path, ip, now);
  if (g.blocked) return true;
  await g.done(ok);
  return false;
}

test('10 mislukte pogingen per minuut voor hetzelfde IP + e-mailadres; daarna even ook de juiste niet', async () => {
  const db = d1();
  const r = [];
  for (let i = 0; i < 10; i++) r.push(await attempt(db, 'a@x.test', false));
  assert.deepEqual(r, Array(10).fill(false));
  assert.equal(await attempt(db, 'a@x.test', true), true);
});

test('geslaagde inlogs tellen niet mee', async () => {
  const db = d1();
  for (let i = 0; i < 30; i++) assert.equal(await attempt(db, 'a@x.test', true), false);
});

test('gedeeld netwerk: een ander e-mailadres op hetzelfde IP mag gewoon; hoofdletters en spaties tellen niet', async () => {
  const db = d1();
  for (let i = 0; i < 10; i++) await attempt(db, 'a@x.test', false);
  assert.equal(await attempt(db, 'b@x.test', false), false);
  assert.equal(await attempt(db, '  A@X.test ', false), true);
  assert.equal(await attempt(db, 'a@x.test', false, { ip: '5.6.7.8' }), false, 'zelfde adres, ander netwerk');
});

test('de volgende minuut begint de teller opnieuw', async () => {
  const db = d1();
  for (let i = 0; i < 10; i++) await attempt(db, 'a@x.test', false);
  assert.equal(await attempt(db, 'a@x.test', false, { now: T + 60_000 }), false);
});

test('code versturen: elke aanvraag telt; andere paden en GET niet', async () => {
  const db = d1();
  const send = '/auth/email-otp/send-verification-otp';
  for (let i = 0; i < 10; i++) assert.equal(await attempt(db, 'a@x.test', true, { path: send }), false);
  assert.equal(await attempt(db, 'a@x.test', true, { path: send }), true);
  assert.equal(await loginGate(db, req('a@x.test', '/auth/get-session'), '/auth/get-session', '1.2.3.4', T), null);
  assert.equal(await loginGate(db, new Request(`https://api.test${SIGN_IN}`), SIGN_IN, '1.2.3.4', T), null, 'GET');
});

test('geen IP of e-mailadres in de database, alleen een hash; na een dag opgeruimd', async () => {
  const db = d1();
  await attempt(db, 'a@x.test', false);
  const [row] = db.raw.prepare('SELECT key FROM login_limits').all();
  assert.match(row.key, /^[0-9a-f]{64}$/);
  assert.equal(row.key, await loginKey('1.2.3.4', 'a@x.test'));
  assert.equal((await cleanup(db, new Date(T + 2 * 86_400_000))).logins, 1);
});
