// Controle van fase 2: alle inlogstappen tegen een draaiende Worker (lokaal met wrangler dev, of staging).
// Codes komen uit test_outbox (TEST_OUTBOX_DOMAIN), dus alleen voor testadressen. Ruimt zijn testaccounts op.
//   node tool/auth_check.mjs http://localhost:8787 --env staging --local
//   node tool/auth_check.mjs https://api-staging.macromatrix.eu --env staging
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import bcrypt from 'bcryptjs';
import http from 'node:http';
import https from 'node:https';

const [base, ...rest] = process.argv.slice(2);
const env = rest.includes('--env') ? rest[rest.indexOf('--env') + 1] : undefined;
// Ook op productie (--env production): alleen testaccounts op het testdomein, die het script zelf weer wist
if (env !== 'staging' && env !== 'production') throw new Error('--env staging of --env production verplicht');
const flags = [rest.includes('--local') ? '--local' : '--remote', ...(env === 'production' ? [] : ['--env', env])];
const DOMAIN = 'test.macromatrix.invalid';
const run = Date.now().toString(36);
const mail = (name) => `${name}-${run}@${DOMAIN}`;

const sql = (s) => JSON.parse(execFileSync('npx', ['wrangler', 'd1', 'execute', 'DB', ...flags, '--json', '--command', s], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })).at(-1).results;
const esc = (s) => s.replaceAll("'", "''");

/** Verzoek zoals de app het doet (node:http stuurt, net als Dart, geen Origin of Sec-Fetch-*). */
function call(path, body, token, extraHeaders = {}) {
  const u = new URL(`${base}/auth${path}`);
  const payload = body === undefined ? undefined : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const req = (u.protocol === 'https:' ? https : http).request(
      u,
      {
        method: body === undefined ? 'GET' : 'POST',
        headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...extraHeaders },
      },
      (res) => {
        let text = '';
        res.on('data', (c) => (text += c));
        res.on('end', () => {
          let data = null;
          try {
            data = JSON.parse(text);
          } catch {}
          resolve({ status: res.statusCode, data, token: res.headers['set-auth-token'] ?? null, headers: res.headers });
        });
      },
    );
    req.on('error', reject);
    req.end(payload);
  });
}

/** De laatste code in het testpostvak voor dit adres en deze soort mail. */
function lastMail(to, kind) {
  return sql(`SELECT kind, token FROM test_outbox WHERE "to" = '${esc(to)}'${kind ? ` AND kind = '${kind}'` : ''} ORDER BY id DESC LIMIT 1`)[0];
}

const steps = [];
const step = async (name, fn) => {
  await fn();
  steps.push(name);
  console.log(`  ok  ${name}`);
};

try {
  sql('DELETE FROM signup_ips; DELETE FROM rateLimit'); // testomgeving: de limieten opnieuw laten beginnen
  const a = mail('a');
  let token;

  await step('zwak wachtwoord geweigerd', async () => {
    const r = await call('/sign-up/email', { email: a, password: 'alleenletters', name: '' });
    assert.equal(r.status, 400);
    assert.equal(r.data.code, 'WEAK_PASSWORD');
  });
  await step('registreren stuurt een code', async () => {
    const r = await call('/sign-up/email', { email: a, password: 'geheim123', name: '', termsVersion: '2026-10-17' });
    assert.equal(r.status, 200, JSON.stringify(r.data));
    assert.equal(r.data.token, null);
    assert.match(lastMail(a, 'confirmation').token, /^\d{6}$/);
    const u = sql(`SELECT termsVersion, termsAcceptedAt, emailVerified FROM "user" WHERE email = '${a}'`)[0];
    assert.equal(u.termsVersion, '2026-10-17');
    assert.ok(u.termsAcceptedAt);
    assert.equal(u.emailVerified, 0);
  });
  await step('inloggen vóór bevestigen: EMAIL_NOT_VERIFIED', async () => {
    const r = await call('/sign-in/email', { email: a, password: 'geheim123' });
    assert.equal(r.status, 403);
    assert.equal(r.data.code, 'EMAIL_NOT_VERIFIED');
  });
  await step('foute code geweigerd, juiste code logt in', async () => {
    const bad = await call('/email-otp/verify-email', { email: a, otp: '000000' === lastMail(a, 'confirmation').token ? '111111' : '000000' });
    assert.equal(bad.status, 400);
    const r = await call('/email-otp/verify-email', { email: a, otp: lastMail(a, 'confirmation').token });
    assert.equal(r.status, 200, JSON.stringify(r.data));
    token = r.token ?? r.data.token;
    assert.ok(token);
  });
  await step('sessie met Bearer-token', async () => {
    const r = await call('/get-session', undefined, token);
    assert.equal(r.status, 200);
    assert.equal(r.data.user.email, a);
    assert.equal(r.data.user.emailVerified, true);
  });
  await step('opnieuw registreren met een bevestigd adres: zelfde antwoord, mail "al een account"', async () => {
    const r = await call('/sign-up/email', { email: a, password: 'anders456', name: '' });
    assert.equal(r.status, 200);
    assert.equal(lastMail(a).kind, 'existing_account');
    // Het wachtwoord bleef ongewijzigd
    assert.equal((await call('/sign-in/email', { email: a, password: 'anders456' })).status, 401);
  });
  await step('inloggen geeft een token', async () => {
    const r = await call('/sign-in/email', { email: a, password: 'geheim123' });
    assert.equal(r.status, 200);
    assert.ok(r.token);
  });
  await step('wachtwoord wijzigen (zwak geweigerd), met melding per mail', async () => {
    assert.equal((await call('/change-password', { currentPassword: 'geheim123', newPassword: 'kort1' }, token)).data.code, 'WEAK_PASSWORD');
    const r = await call('/change-password', { currentPassword: 'geheim123', newPassword: 'nieuw7890' }, token);
    assert.equal(r.status, 200, JSON.stringify(r.data));
    assert.equal(lastMail(a).kind, 'password_changed_notification');
  });
  await step('wachtwoord vergeten: code, nieuw wachtwoord, alle sessies uitgelogd', async () => {
    const t2 = (await call('/sign-in/email', { email: a, password: 'nieuw7890' })).token;
    assert.equal((await call('/email-otp/request-password-reset', { email: a })).status, 200);
    const code = lastMail(a, 'recovery').token;
    assert.match(code, /^\d{6}$/);
    const r = await call('/email-otp/reset-password', { email: a, otp: code, password: 'herstel2468' });
    assert.equal(r.status, 200, JSON.stringify(r.data));
    for (const t of [token, t2]) assert.equal((await call('/get-session', undefined, t)).data, null);
    token = (await call('/sign-in/email', { email: a, password: 'herstel2468' })).token;
    assert.ok(token);
    // Onbekend adres: zelfde antwoord, geen mail
    assert.equal((await call('/email-otp/request-password-reset', { email: mail('niemand') })).status, 200);
    assert.equal(lastMail(mail('niemand')), undefined);
  });
  await step('webversie: Origin van de site toegelaten met CORS, een vreemde Origin niet', async () => {
    const web = await call('/sign-in/email', { email: a, password: 'herstel2468' }, undefined, { origin: 'https://macromatrix.eu' });
    assert.equal(web.status, 200);
    assert.equal(web.headers['access-control-allow-origin'], 'https://macromatrix.eu');
    assert.match(web.headers['access-control-expose-headers'], /set-auth-token/);
    const evil = await call('/sign-in/email', { email: a, password: 'herstel2468' }, undefined, { origin: 'https://evil.example' });
    assert.equal(evil.status, 403);
    assert.equal(evil.headers['access-control-allow-origin'], undefined);
  });
  await step('uitloggen en overal uitloggen', async () => {
    const other = (await call('/sign-in/email', { email: a, password: 'herstel2468' })).token;
    assert.equal((await call('/sign-out', {}, token)).status, 200);
    assert.equal((await call('/get-session', undefined, token)).data, null);
    assert.ok((await call('/get-session', undefined, other)).data);
    const third = (await call('/sign-in/email', { email: a, password: 'herstel2468' })).token;
    assert.equal((await call('/revoke-sessions', {}, third)).status, 200);
    assert.equal((await call('/get-session', undefined, other)).data, null);
  });
  await step('nooit bevestigd en opnieuw registreren: nieuw wachtwoord en nieuwe code', async () => {
    const b = mail('b');
    for (const password of ['eerste111', 'tweede222']) {
      const r = await call('/sign-up/email', { email: b, password, name: '' });
      assert.equal(r.status, 200, JSON.stringify(r.data));
    }
    const r = await call('/email-otp/verify-email', { email: b, otp: lastMail(b, 'confirmation').token });
    assert.equal(r.status, 200, JSON.stringify(r.data));
    assert.equal((await call('/sign-in/email', { email: b, password: 'tweede222' })).status, 200);
  });
  await step('inloglimiet: hoogstens 10 pogingen per minuut per IP', async () => {
    sql('DELETE FROM rateLimit');
    const tries = [];
    for (let i = 0; i < 11; i++) tries.push((await call('/sign-in/email', { email: a, password: 'fout' })).status);
    assert.deepEqual(tries.slice(0, 10), Array(10).fill(401));
    assert.equal(tries[10], 429);
    sql('DELETE FROM rateLimit');
  });
  await step('account uit Supabase (bcrypt): inloggen werkt en het wachtwoord wordt omgezet', async () => {
    const c = mail('supabase');
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    const hash = bcrypt.hashSync('oudwachtwoord1', 10).replace(/^\$2b\$/, '$2a$'); // zoals Supabase (Go: $2a$)
    sql(`INSERT INTO "user" (id, name, email, emailVerified, createdAt, updatedAt) VALUES ('${id}', '', '${c}', 1, '${now}', '${now}');
         INSERT INTO account (id, accountId, providerId, userId, password, createdAt, updatedAt) VALUES ('${id}', '${id}', 'credential', '${id}', '${hash}', '${now}', '${now}')`);
    assert.equal((await call('/sign-in/email', { email: c, password: 'fout' })).status, 401);
    const r = await call('/sign-in/email', { email: c, password: 'oudwachtwoord1' });
    assert.equal(r.status, 200, JSON.stringify(r.data));
    const pw = sql(`SELECT password FROM account WHERE userId = '${id}'`)[0].password;
    assert.ok(!pw.startsWith('$2'), 'omgezet naar scrypt');
    assert.equal((await call('/sign-in/email', { email: c, password: 'oudwachtwoord1' })).status, 200);
  });
  await step('registratielimiet: hoogstens 3 nieuwe accounts per uur per netwerk (bestaande adressen tellen niet)', async () => {
    // a en b waren de eerste twee nieuwe accounts; d is de derde, e de vierde
    assert.equal((await call('/sign-up/email', { email: mail('d'), password: 'geheim123', name: '' })).status, 200);
    const r = await call('/sign-up/email', { email: mail('e'), password: 'geheim123', name: '' });
    assert.equal(r.status, 429, JSON.stringify(r.data));
    assert.match(r.data.message, /new accounts from this network/);
  });
  console.log(`auth_check: ${steps.length} stappen geslaagd`);
} finally {
  sql(`DELETE FROM "user" WHERE email LIKE '%-${run}@${DOMAIN}'; DELETE FROM test_outbox WHERE "to" LIKE '%-${run}@${DOMAIN}'; DELETE FROM signup_ips`);
}
