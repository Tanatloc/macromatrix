// Dagteller in /api/photo (functions/api/photo.js), zonder Cloudflare of Supabase: fetch, de cache en het
// beeldmodel worden nagebootst. Draaien met: node --test test/js/
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { PROMPT, onRequestPost, useQuota } from '../../functions/api/photo.js';

let rpc; // wat photo_quota_use antwoordt: { status, body } of 'throw'
let rpcCalls;
let useCalls;
// De stand vóór het tellen bij een stand na het tellen
const before = (b) => (b?.allowed ? { ...b, used: Math.max(0, b.used - 1) } : b);
let aiCalls;
const store = new Map();

beforeEach(() => {
  rpcCalls = 0;
  useCalls = 0;
  aiCalls = 0;
  store.clear();
  globalThis.caches = {
    default: {
      match: async (req) => (store.has(req.url) ? new Response(store.get(req.url)) : undefined),
      put: async (req, res) => store.set(req.url, await res.text()),
    },
  };
  globalThis.fetch = async (url, init) => {
    if (String(url).endsWith('/auth/v1/user')) return Response.json({ id: 'user-1' });
    // rpc.body is de stand na het tellen (photo_quota_use); photo_quota (alleen lezen, vooraf) geeft die daarvoor
    const m = String(url).match(/\/rest\/v1\/rpc\/(photo_quota_use|photo_quota)$/);
    if (m) {
      rpcCalls++;
      if (m[1] === 'photo_quota_use') useCalls++;
      assert.equal(init.method, 'POST');
      assert.equal(init.headers.Authorization, 'Bearer tok');
      if (rpc === 'throw') throw new TypeError('fetch failed');
      return Response.json(m[1] === 'photo_quota' ? before(rpc.body) : rpc.body, { status: rpc.status });
    }
    throw new Error(`onverwachte fetch ${url}`);
  };
});

const env = {
  AI: {
    run: async () => {
      aiCalls++;
      return { response: '2 eggs, 1 slice of bread' };
    },
  },
};

function photoRequest() {
  const body = new Uint8Array(2000);
  body[0] = 0xff;
  body[1] = 0xd8;
  return new Request('https://app.test/api/photo', { method: 'POST', headers: { Authorization: 'Bearer tok' }, body });
}

test('binnen de dagteller: het model wordt gevraagd en de teller komt mee terug', async () => {
  rpc = { status: 200, body: { allowed: true, used: 2, limit: 3, pro: false } };
  const res = await onRequestPost({ request: photoRequest(), env });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { text: '2 eggs, 1 slice of bread', quota: { used: 2, limit: 3, pro: false } });
  assert.equal(aiCalls, 1);
});

test('dagteller op: 429 met error quota, zonder het model te vragen', async () => {
  rpc = { status: 200, body: { allowed: false, used: 3, limit: 3, pro: false } };
  const res = await onRequestPost({ request: photoRequest(), env });
  assert.equal(res.status, 429);
  assert.deepEqual(await res.json(), { error: 'quota', used: 3, limit: 3, pro: false });
  assert.equal(aiCalls, 0);
});

test('functie bestaat nog niet (PGRST202): werkt zoals vroeger, zonder teller', async () => {
  rpc = { status: 404, body: { code: 'PGRST202', message: 'Could not find the function' } };
  const res = await onRequestPost({ request: photoRequest(), env });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { text: '2 eggs, 1 slice of bread' });
  assert.equal(aiCalls, 1);
});

test('Supabase onbereikbaar of een fout van de teller: 503, zonder het model (geen onbeperkte foto\'s)', async () => {
  for (const r of ['throw', { status: 500, body: { code: '57014', message: 'canceling statement due to statement timeout' } }, { status: 200, body: [] }]) {
    rpc = r;
    const res = await onRequestPost({ request: photoRequest(), env });
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { error: 'unavailable' });
  }
  assert.equal(aiCalls, 0);
});

test('de rem per uur blijft gelden, ook zonder teller', async () => {
  rpc = { status: 404, body: { code: 'PGRST202' } };
  for (let i = 0; i < 30; i++) assert.equal((await onRequestPost({ request: photoRequest(), env })).status, 200);
  const res = await onRequestPost({ request: photoRequest(), env });
  assert.equal(res.status, 429);
  assert.equal((await res.json()).error, 'too_many');
});

test('een kapotte foto kost geen foto van vandaag', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 3, pro: false } };
  const bad = new Request('https://app.test/api/photo', { method: 'POST', headers: { Authorization: 'Bearer tok' }, body: new Uint8Array(10) });
  const res = await onRequestPost({ request: bad, env });
  assert.equal(res.status, 400);
  assert.equal(rpcCalls, 0);
});

test('useQuota: een vreemd antwoord is een storing, alleen PGRST202 is "geen teller"', async () => {
  const f = async () => Response.json([]);
  assert.deepEqual(await useQuota('Bearer tok', f), { down: true });
  const missing = async () => Response.json({ code: 'PGRST202' }, { status: 404 });
  assert.deepEqual(await useQuota('Bearer tok', missing), { missing: true });
  const pro = async () => Response.json({ allowed: true, used: 7, limit: 50, pro: true });
  assert.deepEqual(await useQuota('Bearer tok', pro), { quota: { allowed: true, used: 7, limit: 50, pro: true } });
});

test('te groot zonder Content-Length (gestreamd): 413', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 3, pro: false } };
  const body = new ReadableStream({
    start(c) {
      for (let i = 0; i < 30; i++) c.enqueue(new Uint8Array(64_000));
      c.close();
    },
  });
  const req = new Request('https://app.test/api/photo', { method: 'POST', headers: { Authorization: 'Bearer tok' }, body, duplex: 'half' });
  const res = await onRequestPost({ request: req, env });
  assert.equal(res.status, 413);
  assert.equal(rpcCalls, 0);
  assert.equal(aiCalls, 0);
});

test('de vraag aan het model: bereiding en soort noemen, sausen apart, grammen voor vlees (SU-5)', async () => {
  rpc = { status: 404, body: { code: 'PGRST202' } };
  let sent = '';
  const spy = { AI: { run: async (_, input) => ((sent = input.messages[0].content[0].text), { response: '2 scrambled eggs' }) } };
  const res = await onRequestPost({ request: photoRequest(), env: spy });
  assert.equal((await res.json()).text, '2 scrambled eggs');
  assert.equal(sent, PROMPT);
  for (const word of ['scrambled', 'wholemeal', 'rye', 'cooked ham', 'dressings', 'sausages']) assert.match(PROMPT, new RegExp(word));
});

// --- Storing van het beeldmodel (25-10: Llama 4 Scout viel ± 25 min uit)

const LLAMA = '@cf/meta/llama-4-scout-17b-16e-instruct';
const MISTRAL = '@cf/mistralai/mistral-small-3.1-24b-instruct';

test('Llama valt uit: Mistral Small leest de foto, en pas daarna één keer geteld', async () => {
  rpc = { status: 200, body: { allowed: true, used: 2, limit: 3, pro: false } };
  const models = [];
  const flaky = { AI: { run: async (m) => (models.push(m), m === LLAMA ? Promise.reject(new Error('3040: capacity')) : { response: '1 apple' }) } };
  const res = await onRequestPost({ request: photoRequest(), env: flaky });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { text: '1 apple', quota: { used: 2, limit: 3, pro: false } });
  assert.deepEqual(models, [LLAMA, MISTRAL]);
  assert.equal(useCalls, 1);
});

test('Llama doet er te lang over: na de time-out het reservemodel', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 3, pro: false } };
  const slow = { AI_TIMEOUT_MS: '20', AI: { run: async (m) => (m === LLAMA ? new Promise(() => {}) : { response: '2 eggs' }) } };
  const res = await onRequestPost({ request: photoRequest(), env: slow });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).text, '2 eggs');
});

test('beide modellen weg: 503 ai_unavailable met de teller van vóór de foto, niets geteld', async () => {
  rpc = { status: 200, body: { allowed: true, used: 2, limit: 3, pro: false } };
  const down = { AI: { run: async () => Promise.reject(new Error('3040: capacity')) } };
  const res = await onRequestPost({ request: photoRequest(), env: down });
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), { error: 'ai_unavailable', retry: true, quota: { used: 1, limit: 3, pro: false } });
  assert.equal(useCalls, 0);
});

test('antwoord in het chatformaat (choices) wordt ook gelezen', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 3, pro: false } };
  const chat = { AI: { run: async () => ({ choices: [{ message: { content: '150 g rice, 1 apple' } }] }) } };
  assert.equal((await (await onRequestPost({ request: photoRequest(), env: chat })).json()).text, '150 g rice, 1 apple');
});
