// /api/recipe (functions/api/recipe.js): JSON-LD lezen, de SSRF-bescherming en "alleen Pro".
// Draaien met: node --test test/js/
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  checkRecipeQuota,
  fetchPage,
  isPrivateAddress,
  normaliseRecipe,
  onRequestPost,
  parseJsonLd,
  parseYield,
  resolvesPrivate,
  safeUrl,
  visibleText,
} from '../../functions/api/recipe.js';

const fixture = readFileSync(new URL('./fixtures/recipe.html', import.meta.url), 'utf8');

test('JSON-LD: recept in een @graph, met @type als lijst', () => {
  const r = parseJsonLd(fixture);
  assert.equal(r.name, 'Creamy tomato soup');
  assert.equal(r.servings, 4);
  assert.equal(r.image, 'https://example.com/soup.jpg');
  // Entiteiten en tags weg, dubbele en lege regels weg
  assert.deepEqual(r.ingredients, ['800 g tomatoes', '1 onion', '2 tbsp olive oil', '100 ml cream & a pinch of salt', '1 clove of garlic']);
});

test('JSON-LD: geen recept of kapotte JSON → null', () => {
  assert.equal(parseJsonLd('<script type="application/ld+json">{broken</script>'), null);
  assert.equal(parseJsonLd('<script type="application/ld+json">{"@type":"Article"}</script>'), null);
  assert.equal(parseJsonLd('<html></html>'), null);
});

test('recipeYield in alle vormen', () => {
  assert.equal(parseYield('6 porties'), 6);
  assert.equal(parseYield(['', 'Serves 2']), 2);
  assert.equal(parseYield(3), 3);
  assert.equal(parseYield('a lot'), null);
  assert.equal(parseYield(0), null);
});

test('zichtbare tekst: zonder scripts en stijl, ingekort', () => {
  const t = visibleText(fixture);
  assert.ok(t.startsWith('Creamy tomato soup | Example kitchen'));
  assert.ok(t.includes('Lovely soup.'));
  assert.ok(!t.includes('color: red'));
  assert.ok(!t.includes('recipeIngredient'));
  assert.equal(visibleText(`<p>${'x'.repeat(50000)}</p>`, 100).length, 100);
});

test('normaliseRecipe: antwoord van het model nakijken', () => {
  assert.deepEqual(normaliseRecipe({ name: 'Pancakes', servings: '4', ingredients: ['200 g flour', '', '2 eggs'] }), {
    name: 'Pancakes',
    servings: 4,
    ingredients: ['200 g flour', '2 eggs'],
    image: null,
  });
  assert.equal(normaliseRecipe({ ingredients: [] }), null);
  assert.equal(normaliseRecipe('nope'), null);
});

test('SSRF: alleen http/https naar publieke adressen', () => {
  for (const bad of [
    'ftp://example.com/x',
    'file:///etc/passwd',
    'javascript:alert(1)',
    'http://localhost/',
    'http://foo.localhost/',
    'http://127.0.0.1/',
    'http://2130706433/',
    'http://0x7f.1/',
    'http://127.1/',
    'http://10.1.2.3/',
    'http://172.16.0.1/',
    'http://192.168.1.1/',
    'http://169.254.169.254/latest/meta-data',
    'http://100.64.0.1/',
    'http://0.0.0.0/',
    'http://[::1]/',
    'http://[::ffff:127.0.0.1]/',
    'http://[fd00::1]/',
    'http://[fe80::1]/',
    'http://intranet/',
    'http://printer.local/',
    'http://user:pass@example.com/',
    'http://example.com:8080/',
    'not a url',
  ]) {
    assert.equal(safeUrl(bad), null, bad);
  }
  assert.ok(safeUrl('https://www.example.com/recipes/soup'));
  assert.ok(safeUrl('http://example.com:80/x'));
  assert.ok(safeUrl('http://8.8.8.8/'));
  assert.equal(isPrivateAddress('2606:4700::1111'), false);
  assert.equal(isPrivateAddress('192.168.0.1'), true);
});

test('SSRF: een publieke naam die naar een privéadres wijst, wordt geweigerd', async () => {
  const dns = async (url) => {
    const name = new URL(url).searchParams.get('name');
    const type = new URL(url).searchParams.get('type');
    if (type !== 'A') return Response.json({ Answer: [] });
    return Response.json({ Answer: [{ type: 1, data: name === 'evil.example' ? '127.0.0.1' : '93.184.215.14' }] });
  };
  assert.equal(await resolvesPrivate('evil.example', dns), true);
  assert.equal(await resolvesPrivate('good.example', dns), false);
});

test('fetchPage: een doorverwijzing naar een intern adres wordt niet gevolgd', async () => {
  const calls = [];
  const fetcher = async (url) => {
    if (String(url).startsWith('https://cloudflare-dns.com')) return Response.json({ Answer: [] });
    calls.push(String(url));
    return new Response(null, { status: 302, headers: { Location: 'http://169.254.169.254/latest' } });
  };
  assert.deepEqual(await fetchPage('https://example.com/r', fetcher), { error: 'bad_url' });
  assert.deepEqual(calls, ['https://example.com/r']);
});

test('fetchPage: te groot of geen HTML', async () => {
  const big = async (url) =>
    String(url).startsWith('https://cloudflare-dns.com')
      ? Response.json({})
      : new Response(new Uint8Array(2_100_000), { headers: { 'Content-Type': 'text/html' } });
  assert.deepEqual(await fetchPage('https://example.com/', big), { error: 'too_big' });
  const pdf = async (url) =>
    String(url).startsWith('https://cloudflare-dns.com') ? Response.json({}) : new Response('x', { headers: { 'Content-Type': 'application/pdf' } });
  assert.deepEqual(await fetchPage('https://example.com/', pdf), { error: 'not_html' });
});

test('fetchPage: een gewone pagina, ook na een veilige doorverwijzing', async () => {
  const fetcher = async (url) => {
    if (String(url).startsWith('https://cloudflare-dns.com')) return Response.json({});
    if (String(url) === 'http://example.com/r') return new Response(null, { status: 301, headers: { Location: 'https://example.com/r' } });
    return new Response(fixture, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
  };
  const page = await fetchPage('http://example.com/r', fetcher);
  assert.equal(page.url, 'https://example.com/r');
  assert.ok(page.html.includes('Creamy tomato soup'));
});

test('alleen Pro: geen teller (migratie ontbreekt) → pro_required', async () => {
  const missing = async () => Response.json({ code: 'PGRST202' }, { status: 404 });
  const r = await checkRecipeQuota('Bearer tok', missing);
  assert.equal(r.error.status, 403);
  assert.deepEqual(await r.error.json(), { error: 'pro_required' });
  const down = async () => {
    throw new TypeError('fetch failed');
  };
  assert.deepEqual(await (await checkRecipeQuota('Bearer tok', down)).error.json(), { error: 'pro_required' });
});

test('alleen Pro: gratis → pro_required, Pro op → quota, Pro → toegestaan', async () => {
  const free = async () => Response.json({ allowed: false, used: 0, limit: 0, pro: false });
  assert.deepEqual(await (await checkRecipeQuota('Bearer tok', free)).error.json(), { error: 'pro_required' });
  const full = async () => Response.json({ allowed: false, used: 20, limit: 20, pro: true });
  const f = await checkRecipeQuota('Bearer tok', full);
  assert.equal(f.error.status, 429);
  assert.deepEqual(await f.error.json(), { error: 'quota', used: 20, limit: 20, pro: true });
  const ok = async () => Response.json({ allowed: true, used: 3, limit: 20, pro: true });
  assert.deepEqual((await checkRecipeQuota('Bearer tok', ok)).quota, { allowed: true, used: 3, limit: 20, pro: true });
});

// --- De functie zelf

let rpc;
let aiCalls;
const store = new Map();

beforeEach(() => {
  aiCalls = 0;
  store.clear();
  globalThis.caches = {
    default: {
      match: async (req) => (store.has(req.url) ? new Response(store.get(req.url)) : undefined),
      put: async (req, res) => store.set(req.url, await res.text()),
    },
  };
  globalThis.fetch = async (url, init) => {
    const u = String(url);
    if (u.endsWith('/auth/v1/user')) return Response.json({ id: 'user-1' });
    if (u.endsWith('/rest/v1/rpc/ai_quota_use')) {
      assert.deepEqual(JSON.parse(init.body), { p_kind: 'recipe' });
      return Response.json(rpc.body, { status: rpc.status });
    }
    if (u.startsWith('https://cloudflare-dns.com')) return Response.json({});
    if (u === 'https://example.com/soup') return new Response(fixture, { headers: { 'Content-Type': 'text/html' } });
    if (u === 'https://example.com/plain') {
      return new Response(`<html><body><h1>Pancakes</h1><p>${'Mix it all together and bake. '.repeat(5)}</p></body></html>`, {
        headers: { 'Content-Type': 'text/html' },
      });
    }
    throw new Error(`onverwachte fetch ${u}`);
  };
});

const env = {
  AI: {
    run: async () => {
      aiCalls++;
      return { response: '{"name":"Pancakes","servings":4,"ingredients":["200 g flour","2 eggs","300 ml milk"]}' };
    },
  },
};

const linkRequest = (url) =>
  new Request('https://app.test/api/recipe', {
    method: 'POST',
    headers: { Authorization: 'Bearer tok', 'Content-Type': 'application/json' },
    body: JSON.stringify({ url }),
  });

test('link met JSON-LD: zonder model', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 20, pro: true } };
  const res = await onRequestPost({ request: linkRequest('https://example.com/soup'), env });
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.source, 'jsonld');
  assert.equal(j.servings, 4);
  assert.equal(j.ingredients.length, 5);
  assert.equal(aiCalls, 0);
});

test('link zonder JSON-LD: het model leest de tekst', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 20, pro: true } };
  const j = await (await onRequestPost({ request: linkRequest('https://example.com/plain'), env })).json();
  assert.equal(j.source, 'ai');
  assert.deepEqual(j.ingredients, ['200 g flour', '2 eggs', '300 ml milk']);
  assert.equal(aiCalls, 1);
});

test('link naar een intern adres: bad_url, zonder de teller te verhogen', async () => {
  let counted = false;
  rpc = {
    status: 200,
    get body() {
      counted = true;
      return { allowed: true, used: 1, limit: 20, pro: true };
    },
  };
  const res = await onRequestPost({ request: linkRequest('http://169.254.169.254/'), env });
  assert.equal(res.status, 400);
  assert.equal((await res.json()).error, 'bad_url');
  assert.equal(counted, false);
});

test('migratie ontbreekt: pro_required, ook voor een foto', async () => {
  rpc = { status: 404, body: { code: 'PGRST202' } };
  assert.deepEqual(await (await onRequestPost({ request: linkRequest('https://example.com/soup'), env })).json(), { error: 'pro_required' });
  const photo = new Uint8Array(2000);
  photo[0] = 0xff;
  photo[1] = 0xd8;
  const req = new Request('https://app.test/api/recipe', { method: 'POST', headers: { Authorization: 'Bearer tok', 'Content-Type': 'image/jpeg' }, body: photo });
  const res = await onRequestPost({ request: req, env });
  assert.equal(res.status, 403);
  assert.equal(aiCalls, 0);
});

test('foto van een kookboek met Pro', async () => {
  rpc = { status: 200, body: { allowed: true, used: 2, limit: 20, pro: true } };
  const photo = new Uint8Array(2000);
  photo[0] = 0xff;
  photo[1] = 0xd8;
  const req = new Request('https://app.test/api/recipe', { method: 'POST', headers: { Authorization: 'Bearer tok', 'Content-Type': 'image/jpeg' }, body: photo });
  const j = await (await onRequestPost({ request: req, env })).json();
  assert.equal(j.source, 'photo');
  assert.equal(j.name, 'Pancakes');
  assert.deepEqual(j.quota, { allowed: true, used: 2, limit: 20, pro: true });
});
