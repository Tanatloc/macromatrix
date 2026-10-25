// /api/label (functions/api/label.js): het etiket nakijken en omzetten, en de dagteller (die bij een ontbrekende
// migratie niets tegenhoudt). Draaien met: node --test test/js/
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { checkPer100, normaliseLabel, num, onRequestPost } from '../../functions/api/label.js';
import { firstJsonObject } from '../../functions/_lib/ai.js';

test('num: komma, eenheid en "<0,5"', () => {
  assert.equal(num('12,5 g'), 12.5);
  assert.equal(num('<0,5'), 0.5);
  assert.equal(num(3), 3);
  assert.equal(num('n/a'), null);
  assert.equal(num(null), null);
});

test('per 100 g: kJ wordt kcal en zout wordt natrium', () => {
  const r = normaliseLabel({ basis: '100g', energy_kj: 1046, fat: 3, saturated_fat: 1, carbohydrate: 45, sugars: 5, fibre: 6, protein: 10, salt: 1.2 });
  assert.equal(r.basis, '100g');
  assert.equal(r.from_portion, false);
  assert.equal(r.per100.energy_kcal, 250);
  assert.equal(r.per100.energy_kj, 1046);
  assert.equal(r.per100.salt, 1.2);
  assert.equal(r.per100.sodium, 0.48);
  assert.equal(r.per100.carbohydrates, 45);
  assert.equal(r.per100.fiber, 6);
  assert.equal(r.per100.proteins, 10);
});

test('alleen natrium: zout wordt berekend', () => {
  const r = normaliseLabel({ basis: 'per 100 g', energy_kcal: 100, fat: 1, carbohydrate: 20, protein: 2, sodium: 0.4 });
  assert.equal(r.per100.salt, 1);
});

test('per portie met portiegrootte: omgerekend naar 100 g', () => {
  const r = normaliseLabel({ basis: 'portion', portion_size: 30, portion_unit: 'g', energy_kcal: 120, fat: 6, carbohydrate: 15, protein: 1.5, salt: 0.15 });
  assert.equal(r.from_portion, true);
  assert.equal(r.portion_size, 30);
  assert.equal(r.per100.energy_kcal, 400);
  assert.equal(r.per100.fat, 20);
  assert.equal(r.per100.carbohydrates, 50);
  assert.equal(r.per100.salt, 0.5);
});

test('per portie zonder portiegrootte: no_per100', () => {
  assert.deepEqual(normaliseLabel({ basis: 'portion', energy_kcal: 120 }), { error: 'no_per100' });
});

test('per 100 ml blijft 100 ml', () => {
  const r = normaliseLabel({ basis: '100ml', energy_kcal: 42, carbohydrate: 10.6, sugars: 10.6, protein: 0, fat: 0 });
  assert.equal(r.basis, '100ml');
});

test('onmogelijke waarden vallen weg of worden geweigerd', () => {
  // Verzadigd vet meer dan vet, suikers meer dan koolhydraten: weg
  const r = normaliseLabel({ basis: '100g', energy_kcal: 300, fat: 5, saturated_fat: 9, carbohydrate: 10, sugars: 40, protein: 3 });
  assert.equal(r.per100.saturated_fat, null);
  assert.equal(r.per100.sugars, null);
  assert.ok(r.warnings.includes('dropped_sugars'));
  // Meer dan 100 g per 100 g
  assert.deepEqual(normaliseLabel({ basis: '100g', energy_kcal: 500, fat: 60, carbohydrate: 60, protein: 10 }), { error: 'implausible' });
  // Een macro boven 100 valt weg
  assert.equal(checkPer100({ fat: 150, carbohydrates: 10, proteins: 2 }).per100.fat, null);
  // kcal en kJ omgewisseld
  const swap = normaliseLabel({ basis: '100g', energy_kj: 250, energy_kcal: 1046, fat: 3, carbohydrate: 45, protein: 10 });
  assert.equal(swap.per100.energy_kcal, 250);
  // Niets bruikbaars
  assert.deepEqual(normaliseLabel({ basis: null }), { error: 'unreadable' });
  assert.deepEqual(normaliseLabel({ basis: '100g', fat: 3 }), { error: 'unreadable' });
});

test('kcal en kJ spreken elkaar tegen: de kJ geldt', () => {
  const r = normaliseLabel({ basis: '100g', energy_kj: 2000, energy_kcal: 200, fat: 30, carbohydrate: 40, protein: 5 });
  assert.equal(r.per100.energy_kcal, 478);
  assert.ok(r.warnings.includes('energy_mismatch'));
});

test('naam en merk worden opgekuist', () => {
  const r = normaliseLabel({ basis: '100g', energy_kcal: 100, fat: 1, carbohydrate: 2, protein: 3, name: '  Oat   drink ', brand: 'null' });
  assert.equal(r.name, 'Oat drink');
  assert.equal(r.brand, null);
});

test('firstJsonObject: JSON uit een antwoord met tekst eromheen', () => {
  assert.deepEqual(firstJsonObject('Here you go:\n```json\n{"basis":"100g","name":"a {b}"}\n```'), { basis: '100g', name: 'a {b}' });
  assert.equal(firstJsonObject('no json'), null);
});

// --- De functie zelf, met een nagebootste Supabase, cache en beeldmodel

let rpc;
let charged;
let aiCalls;
const store = new Map();

beforeEach(() => {
  aiCalls = 0;
  charged = 0;
  store.clear();
  globalThis.caches = {
    default: {
      match: async (req) => (store.has(req.url) ? new Response(store.get(req.url)) : undefined),
      put: async (req, res) => store.set(req.url, await res.text()),
    },
  };
  globalThis.fetch = async (url, init) => {
    if (String(url).endsWith('/auth/v1/user')) return Response.json({ id: 'user-1' });
    // rpc.body is de stand na het tellen (ai_quota_use); ai_quota (alleen lezen, vooraf) geeft die daarvoor
    const m = String(url).match(/\/rest\/v1\/rpc\/(ai_quota_use|ai_quota)$/);
    if (m) {
      assert.deepEqual(JSON.parse(init.body), { p_kind: 'label' });
      if (rpc === 'throw') throw new TypeError('fetch failed');
      if (m[1] === 'ai_quota_use') charged++;
      const before = rpc.body?.allowed ? { ...rpc.body, used: Math.max(0, rpc.body.used - 1) } : rpc.body;
      return Response.json(m[1] === 'ai_quota' ? before : rpc.body, { status: rpc.status });
    }
    throw new Error(`onverwachte fetch ${url}`);
  };
});

const env = {
  AI: {
    run: async (_model, input) => {
      aiCalls++;
      const prompt = input.messages[0].content[0].text;
      if (prompt.includes('front of a food package')) return { response: '{"name":"Granola","brand":"Acme"}' };
      return { response: '{"basis":"100g","energy_kj":1900,"energy_kcal":454,"fat":18,"saturated_fat":3,"carbohydrate":60,"sugars":20,"fibre":7,"protein":9,"salt":0.3,"sodium":null,"name":null,"brand":null}' };
    },
  },
};

function jpeg() {
  const b = new Uint8Array(2000);
  b[0] = 0xff;
  b[1] = 0xd8;
  return new Blob([b], { type: 'image/jpeg' });
}

function labelRequest({ front = false } = {}) {
  const f = new FormData();
  f.set('label', jpeg(), 'label.jpg');
  if (front) f.set('front', jpeg(), 'front.jpg');
  return new Request('https://app.test/api/label', { method: 'POST', headers: { Authorization: 'Bearer tok' }, body: f });
}

test('binnen de teller: tabel en voorkant gelezen, met de teller erbij', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 1, pro: false } };
  const res = await onRequestPost({ request: labelRequest({ front: true }), env });
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.name, 'Granola');
  assert.equal(j.brand, 'Acme');
  assert.equal(j.per100.energy_kcal, 454);
  assert.equal(j.per100.sodium, 0.12);
  assert.deepEqual(j.quota, { used: 1, limit: 1, pro: false });
  assert.equal(aiCalls, 2);
});

test('gratis scan van vandaag op: 429 quota zonder het model', async () => {
  rpc = { status: 200, body: { allowed: false, used: 1, limit: 1, pro: false } };
  const res = await onRequestPost({ request: labelRequest(), env });
  assert.equal(res.status, 429);
  assert.deepEqual(await res.json(), { error: 'quota', used: 1, limit: 1, pro: false });
  assert.equal(aiCalls, 0);
});

test('migratie ontbreekt (PGRST202): werkt verder zonder teller', async () => {
  rpc = { status: 404, body: { code: 'PGRST202' } };
  const res = await onRequestPost({ request: labelRequest(), env });
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.quota, undefined);
  assert.equal(aiCalls, 1);
});

test('Supabase onbereikbaar of een andere fout: 503, zonder het model (alleen PGRST202 werkt verder zonder teller)', async () => {
  for (const r of ['throw', { status: 500, body: { code: '57014', message: 'timeout' } }, { status: 400, body: { code: 'P0001', message: 'niet ingelogd' } }, { status: 200, body: [] }]) {
    rpc = r;
    const res = await onRequestPost({ request: labelRequest(), env });
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { error: 'unavailable' });
  }
  assert.equal(aiCalls, 0);
});

test('een oudere migratie die de soort niet kent ("onbekende soort"): werkt verder zonder teller', async () => {
  rpc = { status: 400, body: { code: 'P0001', message: 'onbekende soort' } };
  assert.equal((await onRequestPost({ request: labelRequest(), env })).status, 200);
});

test('te groot zonder Content-Length (gestreamd): 413 zonder alles in te lezen', async () => {
  let pulled = 0;
  const body = new ReadableStream({
    pull(c) {
      pulled++;
      c.enqueue(new Uint8Array(64_000));
      if (pulled > 200) c.close();
    },
  });
  const req = new Request('https://app.test/api/label', {
    method: 'POST',
    headers: { Authorization: 'Bearer tok', 'Content-Type': 'multipart/form-data; boundary=x' },
    body,
    duplex: 'half',
  });
  assert.equal(req.headers.get('Content-Length'), null);
  const res = await onRequestPost({ request: req, env });
  assert.equal(res.status, 413);
  assert.equal((await res.json()).error, 'too_big');
  assert.ok(pulled < 60, `${pulled} stukken gelezen`);
  assert.equal(aiCalls, 0);
});

test('zonder token: login', async () => {
  const req = new Request('https://app.test/api/label', { method: 'POST', body: new FormData() });
  assert.equal((await onRequestPost({ request: req, env })).status, 401);
});

test('geen foto of geen JPEG/PNG: bad_image, zonder teller', async () => {
  rpc = { status: 500, body: {} };
  const f = new FormData();
  f.set('label', new Blob([new Uint8Array(2000)]), 'x.bin');
  const res = await onRequestPost({ request: new Request('https://app.test/api/label', { method: 'POST', headers: { Authorization: 'Bearer tok' }, body: f }), env });
  assert.equal(res.status, 400);
  assert.equal((await res.json()).error, 'bad_image');
});

test('zonder beeldmodel: not_configured', async () => {
  assert.equal((await onRequestPost({ request: labelRequest(), env: {} })).status, 503);
});

// --- Storing van het beeldmodel en tellen na een geslaagde scan

test('Llama valt uit: het reservemodel leest het etiket; één keer geteld', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 1, pro: false } };
  const models = [];
  const flaky = { AI: { run: async (m, input) => (models.push(m), m.includes('llama') ? Promise.reject(new Error('3040')) : env.AI.run(m, input)) } };
  const res = await onRequestPost({ request: labelRequest(), env: flaky });
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.per100.energy_kcal, 454);
  assert.deepEqual(j.quota, { used: 1, limit: 1, pro: false });
  assert.deepEqual(models, ['@cf/meta/llama-4-scout-17b-16e-instruct', '@cf/mistralai/mistral-small-3.1-24b-instruct']);
  assert.equal(charged, 1);
});

test('beide modellen weg: 503 ai_unavailable, de gratis scan van vandaag blijft', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 1, pro: false } };
  const res = await onRequestPost({ request: labelRequest(), env: { AI: { run: async () => Promise.reject(new Error('3040')) } } });
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), { error: 'ai_unavailable', retry: true, quota: { used: 0, limit: 1, pro: false } });
  assert.equal(charged, 0);
});

test('onleesbaar etiket: 422 zonder te tellen', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 1, pro: false } };
  const res = await onRequestPost({ request: labelRequest(), env: { AI: { run: async () => ({ response: 'I cannot read this.' }) } } });
  assert.equal(res.status, 422);
  assert.equal(charged, 0);
});
