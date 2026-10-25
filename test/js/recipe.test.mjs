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
let useCalls;
let peekCalls;
const store = new Map();

beforeEach(() => {
  aiCalls = 0;
  useCalls = 0;
  peekCalls = 0;
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
      useCalls++;
      assert.deepEqual(JSON.parse(init.body), { p_kind: 'recipe' });
      return Response.json(rpc.body, { status: rpc.status });
    }
    // Alleen lezen (ai_quota): dezelfde stand, zonder te tellen
    if (u.endsWith('/rest/v1/rpc/ai_quota')) {
      peekCalls++;
      assert.deepEqual(JSON.parse(init.body), { p_kind: 'recipe' });
      return Response.json(rpc.body, { status: rpc.status });
    }
    if (u.startsWith('https://cloudflare-dns.com')) return Response.json({});
    if (u === 'https://example.com/soup') return new Response(fixture, { headers: { 'Content-Type': 'text/html' } });
    if (u === 'https://example.com/gone') return new Response('not found', { status: 404 });
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

test('een link die niet opengaat, kost geen import van vandaag (pas geteld na het ophalen)', async () => {
  rpc = { status: 200, body: { allowed: true, used: 3, limit: 20, pro: true } };
  const res = await onRequestPost({ request: linkRequest('https://example.com/gone'), env });
  assert.equal(res.status, 422);
  assert.deepEqual(await res.json(), { error: 'fetch_failed', quota: { allowed: true, used: 3, limit: 20, pro: true } });
  assert.equal(peekCalls, 1);
  assert.equal(useCalls, 0);
  // Een link die wel werkt: één keer gelezen en één keer geteld
  assert.equal((await onRequestPost({ request: linkRequest('https://example.com/soup'), env })).status, 200);
  assert.equal(peekCalls, 2);
  assert.equal(useCalls, 1);
});

test('gratis account: pro_required zonder de pagina op te halen', async () => {
  rpc = { status: 200, body: { allowed: false, used: 0, limit: 0, pro: false } };
  const res = await onRequestPost({ request: linkRequest('https://example.com/gone'), env });
  assert.deepEqual(await res.json(), { error: 'pro_required' });
  assert.equal(useCalls, 0);
});

test('vraag te groot (ook zonder Content-Length): 413', async () => {
  rpc = { status: 200, body: { allowed: true, used: 1, limit: 20, pro: true } };
  const body = new ReadableStream({
    start(c) {
      c.enqueue(new TextEncoder().encode(JSON.stringify({ url: `https://example.com/${'a'.repeat(40_000)}` })));
      c.close();
    },
  });
  const req = new Request('https://app.test/api/recipe', {
    method: 'POST',
    headers: { Authorization: 'Bearer tok', 'Content-Type': 'application/json' },
    body,
    duplex: 'half',
  });
  assert.equal((await onRequestPost({ request: req, env })).status, 413);
  assert.equal(peekCalls + useCalls, 0);
});

test('SSRF: 6to4, Teredo, site-local en IPv4 in IPv6 worden geweigerd', () => {
  for (const bad of [
    'http://[2002:7f00:1::]/',
    'http://[2002:a9fe:a9fe::]/',
    'http://[2002:c0a8:101::1]/',
    'http://[fec0::1]/',
    'http://[feff::1]/',
    'http://[2001:0:4136:e378:8000:63bf:3fff:fdd2]/',
    'http://[::127.0.0.1]/',
    'http://[::ffff:a9fe:a9fe]/',
    'http://[64:ff9b::7f00:1]/',
    'http://[ff02::1]/',
    'http://[100::1]/',
  ]) {
    assert.equal(safeUrl(bad), null, bad);
  }
  // 6to4 met een publiek IPv4-adres mag; gewone publieke IPv6 ook
  assert.ok(safeUrl('http://[2002:808:808::1]/'));
  assert.ok(safeUrl('http://[2606:4700::1111]/'));
  assert.equal(isPrivateAddress('2001:4860:4860::8888'), false);
  assert.equal(isPrivateAddress('2001:0:4136:e378::1'), true);
  assert.equal(isPrivateAddress('fec0:0:0:1::1'), true);
  assert.equal(isPrivateAddress('not:an:ip:::x'), true);
});

test('SSRF: lukt het opzoeken van de naam niet, dan wordt de pagina niet opgehaald', async () => {
  const seen = [];
  const make = (dns) => async (url) => {
    seen.push(String(url));
    if (String(url).includes('cloudflare-dns')) return dns();
    return new Response('<html>x</html>', { headers: { 'Content-Type': 'text/html' } });
  };
  for (const dns of [
    () => {
      throw new Error('down');
    },
    () => new Response('busy', { status: 503 }),
    () => Response.json({ Status: 2, Answer: [] }),
  ]) {
    seen.length = 0;
    assert.equal(await resolvesPrivate('rebind.example.com', make(dns)), true);
    assert.deepEqual(await fetchPage('https://rebind.example.com/', make(dns)), { error: 'bad_url' });
    assert.ok(seen.every((u) => u.includes('cloudflare-dns')), seen.join(' '));
  }
  // Bestaat niet (NXDOMAIN): geen privéadres; het ophalen zelf faalt dan
  assert.equal(await resolvesPrivate('nope.example.com', async () => Response.json({ Status: 3 })), false);
});

test('een vijandige pagina blijft snel (geen kwadratische regexen)', () => {
  for (const evil of ['<nav', '<script', '<!--', '<p', '<', '<title', '<script type="application/ld+json">', '<a <p']) {
    const html = evil.repeat(Math.ceil(320_000 / evil.length));
    const t0 = performance.now();
    visibleText(html);
    parseJsonLd(html);
    const ms = performance.now() - t0;
    assert.ok(ms < 200, `${evil}: ${ms.toFixed(0)} ms`);
  }
  // Een enorme ingrediëntregel vol "<" in de JSON-LD
  const ld = `<script type="application/ld+json">${JSON.stringify({ '@type': 'Recipe', recipeIngredient: ['<'.repeat(300_000), '2 eggs'] })}</script>`;
  const t0 = performance.now();
  assert.ok(parseJsonLd(ld).ingredients.includes('2 eggs'));
  assert.ok(performance.now() - t0 < 200);
});

test('zichtbare tekst: blokken, opmerkingen en tags zoals vroeger', () => {
  const t = visibleText(
    '<html><head><title>T</title></head><body><nav>menu</nav><!-- weg --><h1>Soep</h1><p>Lekker<br>warm</p><FOOTER x>f</FOOTER><div>einde</div><nav>open',
  );
  assert.deepEqual(t.split('\n'), ['T', 'Soep', 'Lekker', 'warm', 'einde open']);
  // Een blok zonder einde blijft staan (zoals de regex vroeger), een "<" zonder ">" ook
  assert.equal(visibleText('<p>a < b'), 'a < b');
});
