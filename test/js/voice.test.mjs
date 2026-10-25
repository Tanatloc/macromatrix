// /api/voice (functions/api/voice.js): spraak naar tekst met de dagteller ai_quota_use('voice') en de rem per uur.
// Supabase, de cache en Whisper zijn nagebootst. Draaien met: node --test test/js/
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { onRequestPost } from '../../functions/api/voice.js';
import { readBytes, readJson } from '../../functions/_lib/body.js';

let quota; // wat ai_quota_use('voice') antwoordt: { status, body }, 'throw' of 'atomic' (een echte teller tot 60)
let used;
let quotaCalls;
let whisper;
const store = new Map();

// Zoals de Cache API in Cloudflare: asynchroon, dus parallelle verzoeken lezen allemaal dezelfde stand
const wait = () => new Promise((r) => setTimeout(r, 2));
beforeEach(() => {
  quota = { status: 200, body: { allowed: true, used: 1, limit: 60, pro: false } };
  used = 0;
  quotaCalls = 0;
  whisper = 0;
  store.clear();
  globalThis.caches = {
    default: {
      match: async (req) => (await wait(), store.has(req.url) ? new Response(store.get(req.url)) : undefined),
      put: async (req, res) => (await wait(), store.set(req.url, await res.text())),
    },
  };
});

const fetcher = async (url, init) => {
  const u = String(url);
  if (u.endsWith('/auth/v1/user')) return init.headers.Authorization === 'Bearer tok' ? Response.json({ id: 'user-1' }) : new Response('{}', { status: 401 });
  if (u.endsWith('/rest/v1/rpc/ai_quota_use')) {
    quotaCalls++;
    assert.deepEqual(JSON.parse(init.body), { p_kind: 'voice' });
    if (quota === 'throw') throw new TypeError('fetch failed');
    if (quota === 'atomic') {
      if (used >= 60) return Response.json({ allowed: false, used, limit: 60, pro: false });
      used++;
      return Response.json({ allowed: true, used, limit: 60, pro: false });
    }
    return Response.json(quota.body, { status: quota.status });
  }
  throw new Error(`onverwachte fetch ${u}`);
};

const env = {
  AI: {
    run: async (model, input) => {
      whisper++;
      assert.equal(model, '@cf/openai/whisper-large-v3-turbo');
      assert.equal(input.language, 'nl');
      return { text: ' twee eieren ' };
    },
  },
};

const voiceRequest = (body = new Uint8Array(2000), auth = 'Bearer tok') =>
  new Request('https://app.test/api/voice?lang=nl', { method: 'POST', headers: { Authorization: auth, 'Content-Type': 'audio/wav' }, body });

test('binnen de dagteller: Whisper maakt er tekst van', async () => {
  const res = await onRequestPost({ request: voiceRequest(), env }, fetcher);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { text: 'twee eieren' });
  assert.equal(quotaCalls, 1);
  assert.equal(whisper, 1);
});

test('200 verzoeken tegelijk: de dagteller in de database laat er maar 60 door (de cache alleen niet)', async () => {
  quota = 'atomic';
  const results = await Promise.all(Array.from({ length: 200 }, () => onRequestPost({ request: voiceRequest(), env }, fetcher)));
  assert.equal(whisper, 60);
  assert.equal(results.filter((r) => r.status === 200).length, 60);
  for (const r of results.filter((x) => x.status !== 200)) {
    assert.equal(r.status, 429);
    assert.deepEqual(await r.json(), { error: 'too_many' });
  }
});

test('dagteller op: 429 zonder Whisper; storing van de teller: 503 zonder Whisper', async () => {
  quota = { status: 200, body: { allowed: false, used: 60, limit: 60, pro: false } };
  assert.equal((await onRequestPost({ request: voiceRequest(), env }, fetcher)).status, 429);
  quota = 'throw';
  let res = await onRequestPost({ request: voiceRequest(), env }, fetcher);
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), { error: 'unavailable' });
  quota = { status: 500, body: { code: '57014' } };
  res = await onRequestPost({ request: voiceRequest(), env }, fetcher);
  assert.equal(res.status, 503);
  assert.equal(whisper, 0);
});

test('migratie ontbreekt (PGRST202 of onbekende soort): alleen de rem per uur (60)', async () => {
  quota = { status: 404, body: { code: 'PGRST202' } };
  for (let i = 0; i < 30; i++) assert.equal((await onRequestPost({ request: voiceRequest(), env }, fetcher)).status, 200);
  quota = { status: 400, body: { code: 'P0001', message: 'onbekende soort' } };
  for (let i = 0; i < 30; i++) assert.equal((await onRequestPost({ request: voiceRequest(), env }, fetcher)).status, 200);
  const res = await onRequestPost({ request: voiceRequest(), env }, fetcher);
  assert.equal(res.status, 429);
  assert.equal((await res.json()).error, 'too_many');
  assert.equal(whisper, 60);
});

test('een lege opname kost niets; zonder token: login', async () => {
  assert.deepEqual(await (await onRequestPost({ request: voiceRequest(new Uint8Array(10)), env }, fetcher)).json(), { text: '' });
  assert.equal(quotaCalls, 0);
  assert.equal((await onRequestPost({ request: voiceRequest(undefined, 'Bearer nope'), env }, fetcher)).status, 401);
  assert.equal((await onRequestPost({ request: voiceRequest(), env: {} }, fetcher)).status, 503);
});

test('te lang, ook zonder Content-Length (gestreamd): 413 too_long, zonder teller of Whisper', async () => {
  let pulled = 0;
  const body = new ReadableStream({
    pull(c) {
      pulled++;
      c.enqueue(new Uint8Array(100_000));
      if (pulled > 100) c.close();
    },
  });
  const req = new Request('https://app.test/api/voice', { method: 'POST', headers: { Authorization: 'Bearer tok' }, body, duplex: 'half' });
  assert.equal(req.headers.get('Content-Length'), null);
  const res = await onRequestPost({ request: req, env }, fetcher);
  assert.equal(res.status, 413);
  assert.deepEqual(await res.json(), { error: 'too_long' });
  assert.ok(pulled < 30, `${pulled} stukken gelezen`);
  assert.equal(quotaCalls, 0);
  assert.equal(whisper, 0);
});

test('readBytes en readJson: grens, Content-Length en kapotte JSON', async () => {
  const req = (body, headers = {}) => new Request('https://x/', { method: 'POST', body, headers });
  assert.equal((await readBytes(req('abc'), 3)).bytes.length, 3);
  assert.equal((await readBytes(req('abcd'), 3)).error.status, 413);
  assert.equal((await readBytes(new Request('https://x/', { method: 'POST' }), 3)).bytes.length, 0);
  // Een te grote Content-Length: meteen 413, zonder te lezen
  const big = await readBytes(req('a', { 'Content-Length': '999999' }), 10, { ok: false, reason: 'too_big' });
  assert.equal(big.error.status, 413);
  assert.deepEqual(await big.error.json(), { ok: false, reason: 'too_big' });
  assert.deepEqual((await readJson(req('{"a":1}'), 100)).value, { a: 1 });
  assert.equal((await readJson(req('{'), 100)).bad, true);
});
