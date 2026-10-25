// /api/off-contribute (functions/api/off-contribute.js): delen met Open Food Facts, alleen met de secrets.
// Draaien met: node --test test/js/
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { hasData, onRequestGet, onRequestPost, productFields, USER_AGENT, validBarcode } from '../../functions/api/off-contribute.js';

const store = new Map();
let sent;
let quota; // wat ai_quota_use('off') antwoordt: { status, body } of 'throw'
let blocked; // woorden die text_blocked weigert, of 'down'
let existing; // wat Open Food Facts al over de barcode weet: null (onbekend), een product, of 'down'
let lookups;
let quotaCalls;

beforeEach(() => {
  store.clear();
  sent = [];
  quota = { status: 200, body: { allowed: true, used: 1, limit: 10, pro: false } };
  blocked = [];
  existing = null;
  lookups = [];
  quotaCalls = 0;
  globalThis.caches = {
    default: {
      match: async (req) => (store.has(req.url) ? new Response(store.get(req.url)) : undefined),
      put: async (req, res) => store.set(req.url, await res.text()),
    },
  };
});

const fetcher = async (url, init) => {
  const u = String(url);
  if (u.endsWith('/auth/v1/user')) return Response.json({ id: 'user-1' });
  if (u.endsWith('/rest/v1/rpc/text_blocked')) {
    assert.equal(init.headers.Authorization, 'Bearer tok');
    if (blocked === 'down') return Response.json({ code: '57014' }, { status: 500 });
    return Response.json(blocked.includes(JSON.parse(init.body).p));
  }
  if (u.endsWith('/rest/v1/rpc/ai_quota_use')) {
    quotaCalls++;
    assert.deepEqual(JSON.parse(init.body), { p_kind: 'off' });
    if (quota === 'throw') throw new TypeError('fetch failed');
    return Response.json(quota.body, { status: quota.status });
  }
  if (u.includes('/api/v2/product/')) {
    lookups.push({ url: u, headers: init.headers });
    if (existing === 'down') return new Response('<html>busy</html>', { status: 503 });
    if (!existing) return Response.json({ status: 0, status_verbose: 'product not found' }, { status: 404 });
    return Response.json({ status: 1, product: existing });
  }
  sent.push({ url: u, headers: init.headers, body: init.body });
  if (u.endsWith('/cgi/product_jqm2.pl')) return Response.json({ status: 1, status_verbose: 'fields saved' });
  if (u.endsWith('/cgi/product_image_upload.pl')) return Response.json({ status: 'status ok', imgid: 1 });
  throw new Error(`onverwachte fetch ${u}`);
};

const env = { OFF_USER: 'macromatrix-app', OFF_PASSWORD: 'secret' };

function contributeRequest({ code = '5449000000996', nutriments = { energy_kcal: 42, carbohydrates: 10.6, sugars: 10.6, salt: 0 } } = {}) {
  const f = new FormData();
  f.set('code', code);
  f.set('name', 'Cola');
  f.set('brand', 'Acme');
  f.set('nutriments', JSON.stringify(nutriments));
  const img = new Uint8Array(2000);
  img[0] = 0xff;
  img[1] = 0xd8;
  f.set('label', new Blob([img], { type: 'image/jpeg' }), 'label.jpg');
  return new Request('https://app.test/api/off-contribute', { method: 'POST', headers: { Authorization: 'Bearer tok' }, body: f });
}

test('zonder secrets: not_configured (GET en POST)', async () => {
  assert.deepEqual(await (await onRequestGet({ env: {} })).json(), { configured: false });
  assert.deepEqual(await (await onRequestGet({ env })).json(), { configured: true });
  const res = await onRequestPost({ request: contributeRequest(), env: {} }, fetcher);
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), { error: 'not_configured' });
  assert.equal(sent.length, 0);
});

test('barcode met controlecijfer', () => {
  assert.equal(validBarcode('5449000000996'), true);
  assert.equal(validBarcode('5449000000997'), false);
  assert.equal(validBarcode('96385074'), true);
  assert.equal(validBarcode('abc'), false);
});

test('velden voor Open Food Facts per 100 g', () => {
  const f = productFields({ code: '5449000000996', name: 'Cola', brand: '', per100: { energy_kcal: 42, fat: null, salt: 0.1 } });
  assert.equal(f.nutrition_data_per, '100g');
  assert.equal(f['nutriment_energy-kcal'], '42');
  assert.equal(f['nutriment_energy-kcal_unit'], 'kcal');
  assert.equal(f.nutriment_salt, '0.1');
  assert.equal(f.nutriment_fat, undefined);
  assert.equal(f.brands, undefined);
  assert.equal(f.product_name, 'Cola');
});

test('delen: product en foto met de User-Agent van de app, wachtwoord alleen in de body', async () => {
  const res = await onRequestPost({ request: contributeRequest(), env }, fetcher);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, images: 1, url: 'https://world.openfoodfacts.org/product/5449000000996' });
  assert.equal(sent.length, 2);
  assert.match(USER_AGENT, /^MacroMatrix\/\d+\.\d+\.\d+ \(macromatrix\.eu\)$/);
  for (const s of sent) assert.equal(s.headers['User-Agent'], USER_AGENT);
  const product = sent[0].body;
  assert.equal(product.get('user_id'), 'macromatrix-app');
  assert.equal(product.get('code'), '5449000000996');
  assert.equal(product.get('nutriment_sugars'), '10.6');
  assert.equal(product.get('nutriment_sodium'), '0');
  const image = sent[1].body;
  assert.equal(image.get('imagefield'), 'nutrition_en');
  assert.ok(image.get('imgupload_nutrition_en'));
});

test('verkeerde barcode of onmogelijke waarden: niets verstuurd', async () => {
  assert.equal((await onRequestPost({ request: contributeRequest({ code: '123' }), env }, fetcher)).status, 400);
  const bad = contributeRequest({ nutriments: { energy_kcal: 500, fat: 80, carbohydrates: 80 } });
  assert.equal((await onRequestPost({ request: bad, env }, fetcher)).status, 400);
  assert.equal(sent.length, 0);
});

test('eerst opgezocht bij Open Food Facts, met de User-Agent van de app', async () => {
  assert.equal((await onRequestPost({ request: contributeRequest(), env }, fetcher)).status, 200);
  assert.equal(lookups.length, 1);
  assert.equal(lookups[0].url, 'https://world.openfoodfacts.org/api/v2/product/5449000000996.json?fields=code,product_name,brands,nutriments,images');
  assert.equal(lookups[0].headers['User-Agent'], USER_AGENT);
});

test('bestaat het product al met een naam of voedingswaarden: 409 exists, niets geschreven', async () => {
  for (const p of [{ product_name: 'Coca-Cola' }, { product_name: '', nutriments: { 'energy-kcal_100g': 42 } }, { nutriments: { sugars: '10.6' } }]) {
    existing = p;
    const res = await onRequestPost({ request: contributeRequest(), env }, fetcher);
    assert.equal(res.status, 409);
    assert.equal((await res.json()).error, 'exists');
  }
  assert.equal(sent.length, 0);
});

test('bestaat het product zonder naam en voedingswaarden: aanvullen, maar merk en foto die er staan blijven', async () => {
  existing = { code: '5449000000996', brands: 'The Brand', nutriments: { 'nova-group': 4 }, images: { nutrition_en: { imgid: '1' } } };
  assert.equal(hasData(existing), false);
  const res = await onRequestPost({ request: contributeRequest(), env }, fetcher);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).images, 0);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].body.get('product_name'), 'Cola');
  assert.equal(sent[0].body.get('brands'), null);
});

test('opzoeken lukt niet: 502, niets geschreven', async () => {
  existing = 'down';
  assert.equal((await onRequestPost({ request: contributeRequest(), env }, fetcher)).status, 502);
  assert.equal(sent.length, 0);
});

test('naam of merk met een geweigerd woord: 400 not_allowed; filter onbereikbaar: 503; niets verstuurd', async () => {
  blocked = ['Cola'];
  let res = await onRequestPost({ request: contributeRequest(), env }, fetcher);
  assert.equal(res.status, 400);
  assert.deepEqual(await res.json(), { error: 'not_allowed' });
  blocked = ['Acme'];
  assert.equal((await onRequestPost({ request: contributeRequest(), env }, fetcher)).status, 400);
  blocked = 'down';
  res = await onRequestPost({ request: contributeRequest(), env }, fetcher);
  assert.equal(res.status, 503);
  assert.equal(sent.length, 0);
  assert.equal(quotaCalls, 0);
});

test('dagteller op: 429 too_many; teller onbereikbaar: 503; niets verstuurd', async () => {
  quota = { status: 200, body: { allowed: false, used: 10, limit: 10, pro: false } };
  let res = await onRequestPost({ request: contributeRequest(), env }, fetcher);
  assert.equal(res.status, 429);
  assert.deepEqual(await res.json(), { error: 'too_many' });
  quota = 'throw';
  res = await onRequestPost({ request: contributeRequest(), env }, fetcher);
  assert.equal(res.status, 503);
  quota = { status: 500, body: { code: '57014' } };
  assert.equal((await onRequestPost({ request: contributeRequest(), env }, fetcher)).status, 503);
  assert.equal(sent.length, 0);
  assert.equal(lookups.length, 0);
});

test('veel verzoeken tegelijk: de dagteller in de database houdt ze tegen, niet de cache', async () => {
  // Een teller zoals ai_quota_use: in één stap nakijken en verhogen
  let used = 0;
  const atomic = async (url, init) => {
    if (String(url).endsWith('/rest/v1/rpc/ai_quota_use')) {
      if (used >= 10) return Response.json({ allowed: false, used, limit: 10, pro: false });
      used++;
      return Response.json({ allowed: true, used, limit: 10, pro: false });
    }
    return fetcher(url, init);
  };
  // Een cache zoals in Cloudflare: asynchroon, dus parallelle verzoeken lezen allemaal 0
  const wait = () => new Promise((r) => setTimeout(r, 5));
  globalThis.caches.default = {
    match: async (req) => (await wait(), store.has(req.url) ? new Response(store.get(req.url)) : undefined),
    put: async (req, res) => (await wait(), store.set(req.url, await res.text())),
  };
  const results = await Promise.all(Array.from({ length: 40 }, () => onRequestPost({ request: contributeRequest(), env }, atomic)));
  assert.equal(results.filter((r) => r.status === 200).length, 10);
  assert.equal(sent.filter((x) => x.url.endsWith('/cgi/product_jqm2.pl')).length, 10);
});

test('migratie ontbreekt (PGRST202 of onbekende soort): alleen de rem per uur', async () => {
  quota = { status: 404, body: { code: 'PGRST202' } };
  for (let i = 0; i < 5; i++) assert.equal((await onRequestPost({ request: contributeRequest(), env }, fetcher)).status, 200);
  quota = { status: 400, body: { code: 'P0001', message: 'onbekende soort' } };
  for (let i = 0; i < 5; i++) assert.equal((await onRequestPost({ request: contributeRequest(), env }, fetcher)).status, 200);
  const res = await onRequestPost({ request: contributeRequest(), env }, fetcher);
  assert.equal(res.status, 429);
  assert.equal((await res.json()).error, 'too_many');
});
