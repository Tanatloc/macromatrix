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

/** Een functie op /v1 (buiten /auth), zoals de app: om te zien of een token daar nog werkt. */
async function v1(fn, token) {
  const u = new URL(`${base}/v1/rpc/${fn}`);
  return new Promise((resolve, reject) => {
    const req = (u.protocol === 'https:' ? https : http).request(u, { method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) } }, (res) => {
      res.resume();
      res.on('end', () => resolve(res.statusCode));
    });
    req.on('error', reject);
    req.end('{}');
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
  sql('DELETE FROM signup_ips; DELETE FROM rateLimit; DELETE FROM login_limits'); // testomgeving: de limieten opnieuw laten beginnen
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
    const other = (await call('/sign-in/email', { email: a, password: 'geheim123' })).token;
    // Beide tokens net gebruikt op /v1 (zitten in het geheugen van de Worker)
    assert.deepEqual([await v1('my_pro', token), await v1('my_pro', other)], [200, 200]);
    const r = await call('/change-password', { currentPassword: 'geheim123', newPassword: 'nieuw7890' }, token);
    assert.equal(r.status, 200, JSON.stringify(r.data));
    assert.equal(lastMail(a).kind, 'password_changed_notification');
    // Het andere toestel en het oude token werken meteen nergens meer; dit toestel kreeg een nieuw token
    const fresh = r.token ?? r.data?.token;
    assert.ok(fresh && fresh !== token, 'nieuw token na de wijziging');
    assert.deepEqual([await v1('my_pro', other), await v1('my_pro', token), await v1('my_pro', fresh)], [401, 401, 200]);
    token = fresh;
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
  await step('uitloggen en overal uitloggen: het token werkt meteen nergens meer, ook niet op /v1', async () => {
    const other = (await call('/sign-in/email', { email: a, password: 'herstel2468' })).token;
    assert.deepEqual([await v1('my_pro', token), await v1('my_pro', other)], [200, 200]);
    assert.equal((await call('/sign-out', {}, token)).status, 200);
    assert.equal((await call('/get-session', undefined, token)).data, null);
    assert.equal(await v1('my_pro', token), 401);
    assert.ok((await call('/get-session', undefined, other)).data);
    assert.equal(await v1('my_pro', other), 200);
    const third = (await call('/sign-in/email', { email: a, password: 'herstel2468' })).token;
    assert.equal(await v1('my_pro', third), 200);
    assert.equal((await call('/revoke-sessions', {}, third)).status, 200);
    assert.equal((await call('/get-session', undefined, other)).data, null);
    assert.deepEqual([await v1('my_pro', other), await v1('my_pro', third)], [401, 401]);
  });
  await step('wachtwoord vergeten: een code werkt één keer, verloopt, en is na 5 foute pogingen ongeldig', async () => {
    const reset = (otp, password) => call('/email-otp/reset-password', { email: a, otp, password });
    const code = async () => {
      assert.equal((await call('/email-otp/request-password-reset', { email: a })).status, 200);
      return lastMail(a, 'recovery').token;
    };
    // Eén keer
    const c1 = await code();
    assert.equal((await reset(c1, 'eenmalig1357')).status, 200);
    assert.notEqual((await reset(c1, 'tweemaal2468')).status, 200, 'dezelfde code een tweede keer');
    assert.equal((await call('/sign-in/email', { email: a, password: 'eenmalig1357' })).status, 200);
    // Vijf foute pogingen: daarna werkt ook de juiste code niet meer
    const c2 = await code();
    const wrong = c2 === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) assert.notEqual((await reset(wrong, 'fout0000a')).status, 200);
    assert.notEqual((await reset(c2, 'teveel1357')).status, 200, 'juiste code na 5 foute pogingen');
    // Verlopen (15 min): nagebootst door de vervaltijd in de database terug te zetten
    const c3 = await code();
    sql(`UPDATE verification SET "expiresAt" = '2000-01-01T00:00:00.000Z' WHERE identifier LIKE '%${esc(a)}'`);
    assert.notEqual((await reset(c3, 'verlopen1357')).status, 200, 'verlopen code');
    // Al die foute pogingen tellen ook voor de inloglimiet van dit adres (10 per minuut): eerst die teller terug
    sql('DELETE FROM login_limits');
    // Het wachtwoord is nog steeds dat van de eerste (geslaagde) code
    const back = await call('/sign-in/email', { email: a, password: 'eenmalig1357' });
    assert.equal(back.status, 200, JSON.stringify(back.data));
    token = back.token;
  });
  await step('account verwijderen: het token werkt meteen nergens meer en inloggen kan niet meer', async () => {
    const d = mail('weg');
    assert.equal((await call('/sign-up/email', { email: d, password: 'verdwijn1357', name: '' })).status, 200);
    const t = (await call('/email-otp/verify-email', { email: d, otp: lastMail(d, 'confirmation').token })).token;
    const t2 = (await call('/sign-in/email', { email: d, password: 'verdwijn1357' })).token;
    assert.deepEqual([await v1('my_pro', t), await v1('my_pro', t2)], [200, 200]);
    assert.equal(await v1('delete_account', t), 200);
    assert.deepEqual([await v1('my_pro', t), await v1('my_pro', t2)], [401, 401]);
    assert.equal((await call('/get-session', undefined, t2)).data, null);
    assert.equal((await call('/sign-in/email', { email: d, password: 'verdwijn1357' })).status, 401);
    assert.equal(sql(`SELECT count(*) n FROM "user" WHERE email = '${esc(d)}'`)[0].n, 0);
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
  await step('inloglimiet: 10 pogingen per minuut per IP + e-mailadres; een ander adres op hetzelfde netwerk mag nog', async () => {
    sql('DELETE FROM rateLimit; DELETE FROM login_limits');
    const tries = [];
    for (let i = 0; i < 11; i++) tries.push((await call('/sign-in/email', { email: a, password: 'fout' })).status);
    assert.deepEqual(tries.slice(0, 10), Array(10).fill(401));
    assert.equal(tries[10], 429);
    // Zelfde IP (deze controle), ander account: niet buitengesloten
    assert.equal((await call('/sign-in/email', { email: mail('ander-netwerkgenoot'), password: 'fout' })).status, 401);
    sql('DELETE FROM rateLimit; DELETE FROM login_limits');
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
    // a, b en "weg" (account verwijderen) waren de eerste drie nieuwe accounts van dit netwerk: d is de vierde. Een
    // verwijderd account telt mee (anders kon je de limiet omzeilen door te verwijderen en opnieuw te beginnen).
    const r = await call('/sign-up/email', { email: mail('d'), password: 'geheim123', name: '' });
    assert.equal(r.status, 429, JSON.stringify(r.data));
    assert.match(r.data.message, /new accounts from this network/);
  });
  console.log(`auth_check: ${steps.length} stappen geslaagd`);
} finally {
  sql(`DELETE FROM "user" WHERE email LIKE '%-${run}@${DOMAIN}'; DELETE FROM test_outbox WHERE "to" LIKE '%-${run}@${DOMAIN}'; DELETE FROM signup_ips`);
}
