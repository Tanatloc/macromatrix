// /api/play-verify en /api/play-rtdn (functions/api/play-*.js, functions/_lib/play.js en google.js): een aankoop in
// Google Play nakijken, aan één account koppelen en pro_status bijwerken. Google en Supabase zijn nagebootst; de
// JWT voor Google wordt echt ondertekend met een RSA-sleutel die in de test gemaakt wordt.
// Draaien met: node --test test/js/
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';

import { verify } from '../../functions/api/play-verify.js';
import { rtdn, decodeNotification, sameSecret } from '../../functions/api/play-rtdn.js';
import { evaluateSubscription, accountHash } from '../../functions/_lib/play.js';
import { clearGoogleTokenCache, pemToPkcs8, signJwt, PACKAGE } from '../../functions/_lib/google.js';

const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  publicKeyEncoding: { type: 'spki', format: 'pem' },
});

const SA = {
  type: 'service_account',
  client_email: 'play-verify@example.iam.gserviceaccount.com',
  private_key: privateKey,
  private_key_id: 'kid-1',
  token_uri: 'https://oauth2.googleapis.com/token',
};
const env = { GOOGLE_PLAY_SA: JSON.stringify(SA), SUPABASE_SERVICE_ROLE_KEY: 'eyJservice', PLAY_RTDN_SECRET: 'rtdn-secret-123' };

const NOW = Date.parse('2026-11-05T12:00:00Z');
const day = 86_400_000;
const iso = (t) => new Date(t).toISOString();

// --- Nagebootst: Google (token + Play API) en Supabase (PostgREST met de service-role)

let subs; // purchaseToken → antwoord van subscriptionsv2
let acks;
let tokenCalls;
let db; // { play_purchases: [], pro_status: [] }
let calls;
const users = { 'Bearer user-a': 'aaaaaaaa-0000-0000-0000-000000000001', 'Bearer user-b': 'bbbbbbbb-0000-0000-0000-000000000002' };
const A = users['Bearer user-a'];
const B = users['Bearer user-b'];
const store = new Map();

beforeEach(() => {
  clearGoogleTokenCache();
  subs = new Map();
  acks = [];
  tokenCalls = 0;
  calls = [];
  db = { play_purchases: [], pro_status: [] };
  store.clear();
  globalThis.caches = {
    default: {
      match: async (req) => (store.has(req.url) ? new Response(store.get(req.url)) : undefined),
      put: async (req, res) => store.set(req.url, await res.text()),
    },
  };
});

const DATE_COLS = new Set(['until', 'expiry', 'updated_at']);
function matches(row, params) {
  for (const [k, v] of params) {
    if (['select', 'order', 'limit', 'on_conflict'].includes(k)) continue;
    const dot = v.indexOf('.');
    const op = v.slice(0, dot);
    const val = v.slice(dot + 1);
    const a = DATE_COLS.has(k) ? Date.parse(row[k]) : row[k];
    const b = DATE_COLS.has(k) ? Date.parse(val) : val;
    const ok = { eq: a === b, neq: a !== b, lt: a < b, gt: a > b }[op];
    if (!ok) return false;
  }
  return true;
}

function supabase(u, init) {
  assert.equal(init.headers.apikey, 'eyJservice');
  assert.equal(init.headers.Authorization, 'Bearer eyJservice');
  const table = u.pathname.replace('/rest/v1/', '');
  const rows = db[table];
  assert.ok(rows, `onbekende tabel ${table}`);
  const method = init.method ?? 'GET';
  const params = [...u.searchParams];
  const key = table === 'play_purchases' ? 'purchase_token' : 'user_id';
  calls.push(`${method} ${table}`);
  if (method === 'GET') {
    let out = rows.filter((r) => matches(r, params));
    if (u.searchParams.get('order') === 'expiry.desc') out.sort((x, y) => Date.parse(y.expiry) - Date.parse(x.expiry));
    if (u.searchParams.get('limit')) out = out.slice(0, Number(u.searchParams.get('limit')));
    return Response.json(out);
  }
  const body = JSON.parse(init.body);
  if (method === 'PATCH') {
    const hit = rows.filter((r) => matches(r, params));
    for (const r of hit) Object.assign(r, body);
    return init.headers.Prefer?.includes('return=representation') ? Response.json(hit) : new Response(null, { status: 204 });
  }
  if (method === 'POST') {
    const old = rows.find((r) => r[key] === body[key]);
    if (old) {
      if (init.headers.Prefer.includes('merge-duplicates')) Object.assign(old, body);
    } else rows.push({ ...body });
    return new Response(null, { status: 201 });
  }
  throw new Error(`onverwacht ${method}`);
}

const fetcher = async (url, init = {}) => {
  const u = new URL(String(url));
  if (u.pathname === '/auth/v1/user') {
    const id = users[init.headers.Authorization];
    return id ? Response.json({ id }) : Response.json({ msg: 'bad jwt' }, { status: 401 });
  }
  if (u.host === 'oauth2.googleapis.com') {
    tokenCalls++;
    const form = new URLSearchParams(init.body);
    assert.equal(form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
    const [h, c, s] = form.get('assertion').split('.');
    // De handtekening echt nakijken met de publieke sleutel
    const v = createVerify('RSA-SHA256');
    v.update(`${h}.${c}`);
    assert.ok(v.verify(publicKey, Buffer.from(s, 'base64url')), 'handtekening klopt niet');
    const header = JSON.parse(Buffer.from(h, 'base64url'));
    const claims = JSON.parse(Buffer.from(c, 'base64url'));
    assert.equal(header.alg, 'RS256');
    assert.equal(claims.iss, SA.client_email);
    assert.equal(claims.scope, 'https://www.googleapis.com/auth/androidpublisher');
    assert.equal(claims.aud, 'https://oauth2.googleapis.com/token');
    return Response.json({ access_token: 'ya29.test', expires_in: 3600 });
  }
  if (u.host === 'androidpublisher.googleapis.com') {
    assert.equal(init.headers.Authorization, 'Bearer ya29.test');
    const base = `/androidpublisher/v3/applications/${PACKAGE}/purchases/`;
    assert.ok(u.pathname.startsWith(base), u.pathname);
    const rest = decodeURIComponent(u.pathname.slice(base.length));
    if (rest.startsWith('subscriptionsv2/tokens/')) {
      const sub = subs.get(rest.slice('subscriptionsv2/tokens/'.length));
      return sub ? Response.json(sub) : Response.json({ error: { code: 404 } }, { status: 404 });
    }
    const m = /^subscriptions\/([^/]+)\/tokens\/(.+):acknowledge$/.exec(rest);
    if (m && init.method === 'POST') {
      acks.push({ product: m[1], token: m[2] });
      return new Response('', { status: 200 });
    }
  }
  if (u.host === 'hvqbqgxpksxmavopngap.supabase.co') return supabase(u, init);
  throw new Error(`onverwachte fetch ${u}`);
};

function sub({ state = 'SUBSCRIPTION_STATE_ACTIVE', product = 'pro_yearly', expiry = NOW + 300 * day, ack = 'ACKNOWLEDGEMENT_STATE_PENDING', linked, tag } = {}) {
  return {
    kind: 'androidpublisher#subscriptionPurchaseV2',
    subscriptionState: state,
    acknowledgementState: ack,
    lineItems: [{ productId: product, expiryTime: iso(expiry), autoRenewingPlan: { autoRenewEnabled: true } }],
    ...(linked ? { linkedPurchaseToken: linked } : {}),
    ...(tag ? { externalAccountIdentifiers: { obfuscatedExternalAccountId: tag } } : {}),
  };
}

function req(body, auth = 'Bearer user-a') {
  return new Request('https://app.divinenet.online/api/play-verify', {
    method: 'POST',
    headers: { Authorization: auth, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}
const buy = (token, product = 'pro_yearly', auth) => req({ purchaseToken: token, productId: product, packageName: PACKAGE }, auth);

async function call(r, e = env) {
  const res = await verify(r, e, fetcher, NOW);
  return { status: res.status, body: await res.json() };
}

// --- Google: JWT en beoordeling

test('JWT: RS256 met de sleutel van het serviceaccount, en de PEM wordt goed gelezen', async () => {
  const jwt = await signJwt(SA, 'scope-x', NOW);
  const [h, c, s] = jwt.split('.');
  const v = createVerify('RSA-SHA256');
  v.update(`${h}.${c}`);
  assert.ok(v.verify(publicKey, Buffer.from(s, 'base64url')));
  const claims = JSON.parse(Buffer.from(c, 'base64url'));
  assert.equal(claims.exp - claims.iat, 3600);
  assert.equal(claims.iat, Math.floor(NOW / 1000));
  assert.ok(pemToPkcs8(privateKey).length > 1000);
});

test('beoordeling: actief, respijt, opgezegd maar betaald, afgelopen, in de wacht, bezig, ander product', () => {
  const ev = (o) => evaluateSubscription(sub(o), NOW);
  assert.equal(ev({}).entitled, true);
  assert.equal(ev({ state: 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', expiry: NOW + 3 * day }).entitled, true);
  assert.equal(ev({ state: 'SUBSCRIPTION_STATE_CANCELED', expiry: NOW + day }).entitled, true);
  assert.equal(ev({ state: 'SUBSCRIPTION_STATE_CANCELED', expiry: NOW - day }).reason, 'expired');
  assert.equal(ev({ state: 'SUBSCRIPTION_STATE_EXPIRED', expiry: NOW - day }).reason, 'expired');
  assert.equal(ev({ state: 'SUBSCRIPTION_STATE_ON_HOLD', expiry: NOW + day }).reason, 'expired');
  assert.equal(ev({ state: 'SUBSCRIPTION_STATE_PENDING' }).reason, 'pending');
  assert.equal(ev({ product: 'coins_100' }).reason, 'product');
  // De laatste vervaldatum over alle regels
  const two = sub();
  two.lineItems.push({ productId: 'pro_monthly', expiryTime: iso(NOW + 400 * day) });
  assert.equal(evaluateSubscription(two, NOW).until, NOW + 400 * day);
  assert.equal(evaluateSubscription(two, NOW).product, 'pro_monthly');
});

// --- /api/play-verify

test('actief abonnement: ok, Pro tot de vervaldatum, gekoppeld aan het account en ook door de server bevestigd', async () => {
  subs.set('tok-active-1', sub({ expiry: NOW + 365 * day }));
  const r = await call(buy('tok-active-1'));
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { ok: true, until: iso(NOW + 365 * day) });
  assert.equal(db.pro_status.length, 1);
  assert.equal(db.pro_status[0].user_id, A);
  assert.equal(db.pro_status[0].source, 'play');
  assert.equal(db.pro_status[0].until, iso(NOW + 365 * day));
  assert.deepEqual(
    db.play_purchases.map((p) => [p.purchase_token, p.user_id, p.product, p.expiry]),
    [['tok-active-1', A, 'pro_yearly', iso(NOW + 365 * day)]],
  );
  assert.deepEqual(acks, [{ product: 'pro_yearly', token: 'tok-active-1' }]);
});

test('al bevestigd: niet opnieuw bevestigen; het Google-token wordt hergebruikt', async () => {
  subs.set('tok-acked-01', sub({ ack: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED' }));
  assert.equal((await call(buy('tok-acked-01'))).body.ok, true);
  assert.equal((await call(buy('tok-acked-01'))).body.ok, true);
  assert.deepEqual(acks, []);
  assert.equal(tokenCalls, 1);
});

test('afgelopen abonnement: geweigerd, geen Pro', async () => {
  subs.set('tok-expired-1', sub({ state: 'SUBSCRIPTION_STATE_EXPIRED', expiry: NOW - day }));
  const r = await call(buy('tok-expired-1'));
  assert.deepEqual(r.body, { ok: false, reason: 'expired' });
  assert.equal(db.pro_status.length, 0);
  assert.equal(db.play_purchases.length, 0);
  assert.deepEqual(acks, []);
});

test('betaling nog bezig: pending, geen Pro', async () => {
  subs.set('tok-pending-1', sub({ state: 'SUBSCRIPTION_STATE_PENDING' }));
  assert.deepEqual((await call(buy('tok-pending-1'))).body, { ok: false, reason: 'pending' });
  assert.equal(db.pro_status.length, 0);
});

test('onbekend token bij Google: invalid', async () => {
  const r = await call(buy('tok-unknown-1'));
  assert.equal(r.status, 400);
  assert.equal(r.body.reason, 'invalid');
});

test('een aankoop die al aan een ander account hangt: other_account, en niets verandert', async () => {
  subs.set('tok-shared-01', sub());
  assert.equal((await call(buy('tok-shared-01', 'pro_yearly', 'Bearer user-a'))).body.ok, true);
  const r = await call(buy('tok-shared-01', 'pro_yearly', 'Bearer user-b'));
  assert.equal(r.status, 409);
  assert.deepEqual(r.body, { ok: false, reason: 'other_account' });
  assert.equal(db.play_purchases[0].user_id, A);
  assert.equal(db.pro_status.filter((s) => s.user_id === B).length, 0);
});

test('obfuscatedAccountId van een ander account: other_account; van hetzelfde account: ok', async () => {
  subs.set('tok-tagged-01', sub({ tag: await accountHash(A) }));
  assert.equal((await call(buy('tok-tagged-01', 'pro_yearly', 'Bearer user-b'))).body.reason, 'other_account');
  assert.equal(db.play_purchases.length, 0);
  assert.equal((await call(buy('tok-tagged-01', 'pro_yearly', 'Bearer user-a'))).body.ok, true);
});

test('linkedPurchaseToken (wissel of nieuw abonnement): hoort bij hetzelfde account', async () => {
  subs.set('tok-monthly-1', sub({ product: 'pro_monthly', expiry: NOW + 20 * day }));
  assert.equal((await call(buy('tok-monthly-1', 'pro_monthly'))).body.ok, true);
  // Van maand naar jaar: nieuw token, gekoppeld aan het vorige
  subs.set('tok-yearly-1', sub({ linked: 'tok-monthly-1', expiry: NOW + 365 * day }));
  assert.equal((await call(buy('tok-yearly-1', 'pro_yearly', 'Bearer user-b'))).body.reason, 'other_account');
  const r = await call(buy('tok-yearly-1'));
  assert.equal(r.body.ok, true);
  const row = db.play_purchases.find((p) => p.purchase_token === 'tok-yearly-1');
  assert.equal(row.user_id, A);
  assert.equal(row.linked_purchase_token, 'tok-monthly-1');
  assert.equal(db.pro_status[0].until, iso(NOW + 365 * day));
});

test('nooit een langere Pro inkorten (levenslang met de hand blijft levenslang)', async () => {
  db.pro_status.push({ user_id: A, until: '9999-12-31T00:00:00.000Z', source: 'manual', show_badge: false });
  subs.set('tok-lifetime-1', sub({ expiry: NOW + 30 * day }));
  const r = await call(buy('tok-lifetime-1'));
  assert.equal(r.body.ok, true);
  assert.deepEqual(db.pro_status, [{ user_id: A, until: '9999-12-31T00:00:00.000Z', source: 'manual', show_badge: false }]);
  // Een kortere Pro wordt wel verlengd, en de rest van de rij (badge, rand) blijft
  db.pro_status[0] = { user_id: A, until: iso(NOW + day), source: 'manual', show_badge: false, frame: 'glow' };
  await call(buy('tok-lifetime-1'));
  assert.deepEqual(db.pro_status, [{ user_id: A, until: iso(NOW + 30 * day), source: 'play', show_badge: false, frame: 'glow', updated_at: db.pro_status[0].updated_at }]);
});

test('secrets ontbreken: 503 not_configured, zonder Google of Supabase te vragen', async () => {
  for (const e of [{}, { GOOGLE_PLAY_SA: env.GOOGLE_PLAY_SA }, { SUPABASE_SERVICE_ROLE_KEY: 'x' }, { GOOGLE_PLAY_SA: '{kapot', SUPABASE_SERVICE_ROLE_KEY: 'x' }]) {
    const r = await call(buy('tok-active-1'), e);
    assert.equal(r.status, 503);
    assert.deepEqual(r.body, { ok: false, reason: 'not_configured' });
  }
  assert.equal(tokenCalls, 0);
  assert.deepEqual(calls, []);
});

test('niet ingelogd, slechte vraag, ander pakket, ander product', async () => {
  assert.equal((await call(buy('tok-active-1', 'pro_yearly', 'Bearer nobody'))).status, 401);
  assert.equal((await call(req({ productId: 'pro_yearly' }))).body.reason, 'bad_request');
  assert.equal((await call(req({ purchaseToken: 'tok-active-1', productId: 'coins' }))).body.reason, 'product');
  assert.equal((await call(req({ purchaseToken: 'tok-active-1', productId: 'pro_yearly', packageName: 'com.other' }))).body.reason, 'package');
  const bad = new Request('https://x/api/play-verify', { method: 'POST', headers: { Authorization: 'Bearer user-a' }, body: '{' });
  assert.equal((await call(bad)).body.reason, 'bad_request');
  assert.equal(tokenCalls, 0);
});

test('rem per uur: na 30 keer too_many', async () => {
  subs.set('tok-active-1', sub());
  for (let i = 0; i < 30; i++) assert.equal((await call(buy('tok-active-1'))).status, 200);
  const r = await call(buy('tok-active-1'));
  assert.equal(r.status, 429);
  assert.equal(r.body.reason, 'too_many');
});

test('Google of Supabase faalt: 502 failed, zonder tokens in het logboek', async () => {
  const logs = [];
  const orig = console.log;
  console.log = (...a) => logs.push(a.join(' '));
  try {
    subs.set('tok-secret-xyz', sub());
    const broken = async (url, init) => (String(url).includes('androidpublisher') ? new Response('boom', { status: 500 }) : fetcher(url, init));
    const res = await verify(buy('tok-secret-xyz'), env, broken, NOW);
    assert.equal(res.status, 502);
    assert.equal((await res.json()).reason, 'failed');
  } finally {
    console.log = orig;
  }
  assert.ok(logs.length > 0);
  for (const l of logs) {
    assert.ok(!l.includes('tok-secret-xyz'));
    assert.ok(!l.includes('ya29'));
    assert.ok(!l.includes('PRIVATE KEY'));
  }
});

// --- /api/play-rtdn

function push(notification, secret = 'rtdn-secret-123') {
  const data = Buffer.from(JSON.stringify(notification)).toString('base64');
  return new Request(`https://app.divinenet.online/api/play-rtdn?secret=${encodeURIComponent(secret)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: { data, messageId: '1' }, subscription: 'projects/x/subscriptions/play' }),
  });
}
const note = (token, type = 2) => ({
  version: '1.0',
  packageName: PACKAGE,
  eventTimeMillis: String(NOW),
  subscriptionNotification: { version: '1.0', notificationType: type, purchaseToken: token, subscriptionId: 'pro_yearly' },
});
async function rcall(r, e = env, now = NOW) {
  const res = await rtdn(r, e, fetcher, now);
  return { status: res.status, body: await res.json() };
}

test('rtdn: geheim nodig, secrets nodig', async () => {
  assert.equal((await rcall(push(note('tok-x-123456'), 'fout'))).status, 403);
  assert.equal((await rcall(push(note('tok-x-123456'), ''))).status, 403);
  assert.equal((await rcall(push(note('tok-x-123456')), { ...env, PLAY_RTDN_SECRET: '' })).status, 503);
  assert.equal((await rcall(push(note('tok-x-123456')), { PLAY_RTDN_SECRET: 'rtdn-secret-123' })).status, 503);
  assert.equal(tokenCalls, 0);
  assert.ok(sameSecret('abc', 'abc'));
  assert.ok(!sameSecret('abc', 'abd'));
  assert.ok(!sameSecret('abc', 'abcd'));
});

test('rtdn: verlenging schuift until op zonder dat de app open is', async () => {
  subs.set('tok-renew-01', sub({ expiry: NOW + 2 * day }));
  assert.equal((await call(buy('tok-renew-01'))).body.ok, true);
  subs.set('tok-renew-01', sub({ expiry: NOW + 367 * day, ack: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED' }));
  const r = await rcall(push(note('tok-renew-01', 2)));
  assert.deepEqual(r.body, { ok: true, until: iso(NOW + 367 * day) });
  assert.equal(db.pro_status[0].until, iso(NOW + 367 * day));
  assert.equal(db.play_purchases[0].expiry, iso(NOW + 367 * day));
});

test('rtdn: terugbetaald (revoked) zet until op nu; Pro met de hand blijft staan', async () => {
  subs.set('tok-refund-01', sub({ expiry: NOW + 300 * day }));
  await call(buy('tok-refund-01'));
  subs.set('tok-refund-01', sub({ state: 'SUBSCRIPTION_STATE_EXPIRED', expiry: NOW - 1000 }));
  const r = await rcall(push(note('tok-refund-01', 12)));
  assert.deepEqual(r.body, { ok: true, result: 'expired' });
  assert.equal(db.pro_status[0].until, iso(NOW));
  assert.equal(db.play_purchases[0].expiry, iso(NOW - 1000));

  // Zelfde melding, maar intussen met de hand levenslang gekregen: niet aankomen
  db.pro_status[0] = { user_id: A, until: '9999-12-31T00:00:00.000Z', source: 'manual' };
  await rcall(push(note('tok-refund-01', 12)));
  assert.equal(db.pro_status[0].until, '9999-12-31T00:00:00.000Z');
});

test('rtdn: opgezegd maar betaald loopt door tot de vervaldatum; daarna afgelopen', async () => {
  subs.set('tok-cancel-01', sub({ expiry: NOW + 10 * day }));
  await call(buy('tok-cancel-01'));
  subs.set('tok-cancel-01', sub({ state: 'SUBSCRIPTION_STATE_CANCELED', expiry: NOW + 10 * day }));
  assert.equal((await rcall(push(note('tok-cancel-01', 3)))).body.ok, true);
  assert.equal(db.pro_status[0].until, iso(NOW + 10 * day));
  subs.set('tok-cancel-01', sub({ state: 'SUBSCRIPTION_STATE_EXPIRED', expiry: NOW + 10 * day }));
  await rcall(push(note('tok-cancel-01', 13)), env, NOW + 11 * day);
  assert.equal(db.pro_status[0].until, iso(NOW + 10 * day));
});

test('rtdn: het oude token na een wissel loopt af, maar de nieuwe aankoop houdt Pro aan', async () => {
  subs.set('tok-old-month', sub({ product: 'pro_monthly', expiry: NOW + 20 * day }));
  await call(buy('tok-old-month', 'pro_monthly'));
  subs.set('tok-new-year1', sub({ linked: 'tok-old-month', expiry: NOW + 365 * day }));
  // De melding van de nieuwe aankoop komt voor de app ze meldt: via het gekoppelde token bij hetzelfde account
  assert.equal((await rcall(push(note('tok-new-year1', 4)))).body.ok, true);
  assert.equal(db.play_purchases.find((p) => p.purchase_token === 'tok-new-year1').user_id, A);
  subs.set('tok-old-month', sub({ product: 'pro_monthly', state: 'SUBSCRIPTION_STATE_EXPIRED', expiry: NOW }));
  await rcall(push(note('tok-old-month', 13)));
  assert.equal(db.pro_status[0].until, iso(NOW + 365 * day));
});

test('rtdn: onbekende aankoop, test, ander pakket en een terugbetaling (voided)', async () => {
  subs.set('tok-never-seen', sub());
  assert.deepEqual((await rcall(push(note('tok-never-seen')))).body, { ok: true, result: 'unknown' });
  assert.equal(db.pro_status.length, 0);
  assert.deepEqual((await rcall(push({ version: '1.0', packageName: PACKAGE, testNotification: { version: '1.0' } }))).body, { ok: true, ignored: 'test' });
  assert.deepEqual((await rcall(push({ ...note('tok-never-seen'), packageName: 'com.other' }))).body, { ok: true, ignored: 'other' });

  subs.set('tok-voided-01', sub());
  await call(buy('tok-voided-01'));
  subs.set('tok-voided-01', sub({ state: 'SUBSCRIPTION_STATE_EXPIRED', expiry: NOW - 5 }));
  const voided = { version: '1.0', packageName: PACKAGE, voidedPurchaseNotification: { purchaseToken: 'tok-voided-01', orderId: 'GPA.1', productType: 1, refundType: 1 } };
  assert.equal((await rcall(push(voided))).body.result, 'expired');
  assert.equal(db.pro_status[0].until, iso(NOW));
});

test('rtdn: Google faalt → 502 zodat Pub/Sub opnieuw probeert', async () => {
  db.play_purchases.push({ purchase_token: 'tok-retry-001', user_id: A, product: 'pro_yearly', expiry: iso(NOW) });
  const broken = async (url, init) => (String(url).includes('androidpublisher') ? new Response('', { status: 503 }) : fetcher(url, init));
  const res = await rtdn(push(note('tok-retry-001')), env, broken, NOW);
  assert.equal(res.status, 502);
});

test('decodeNotification: kapot of leeg geeft null', () => {
  assert.equal(decodeNotification({}), null);
  assert.equal(decodeNotification({ message: { data: '!!!' } }), null);
  assert.deepEqual(decodeNotification({ message: { data: Buffer.from('{"a":1}').toString('base64') } }), { a: 1 });
});
