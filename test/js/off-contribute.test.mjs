// /api/off-contribute (functions/api/off-contribute.js): delen met Open Food Facts, alleen met de secrets.
// Draaien met: node --test test/js/
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { onRequestGet, onRequestPost, productFields, USER_AGENT, validBarcode } from '../../functions/api/off-contribute.js';

const store = new Map();
let sent;

beforeEach(() => {
  store.clear();
  sent = [];
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
