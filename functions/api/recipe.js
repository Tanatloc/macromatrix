// Cloudflare Pages Function: een recept importeren uit een link of uit een foto van een kookboekpagina (alleen Pro).
//
// Link: de app stuurt {"url": "..."}. Deze functie haalt de pagina zelf op (alleen http/https, geen adressen in een
// privénetwerk of op deze machine, hoogstens 2 MB en 10 s) en leest het schema.org-recept (JSON-LD:
// recipeIngredient, recipeYield, name, image). Staat dat er niet, dan leest het tekstmodel de zichtbare tekst.
// Foto: de app stuurt een verkleinde JPEG (Content-Type image/jpeg); het beeldmodel leest titel, porties en
// ingrediënten.
// Antwoord: {name, servings, ingredients: [regels], image, source}. De app zoekt elke regel op zoals bij Snel loggen.
// Niets wordt bewaard. Dagteller ai_quota_use('recipe'): gratis 0, met Pro 20 per dag (migratie
// 20261027000000_ai_quota). Zonder die teller kan Pro niet nagekeken worden: dan pro_required.

import { MODEL, MAX_IMAGE_BYTES, checkLogin, dataUrl, hourly, imageType, json, modelObject, useAiQuota } from '../_lib/ai.js';

const PER_HOUR = 20;
const MAX_PAGE_BYTES = 2_000_000;
const FETCH_TIMEOUT_MS = 10_000;
const MAX_REDIRECTS = 3;
const MAX_TEXT = 12_000;
const MAX_LINES = 60;

const USER_AGENT = 'MacroMatrix/1.13.0 (macromatrix.eu)';

// ---------------------------------------------------------------------------------------------------------------
// Tegen SSRF: alleen gewone adressen op het internet

function ipv4Private(ip) {
  const p = ip.split('.').map(Number);
  if (p.length !== 4 || p.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return true;
  const [a, b] = p;
  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 192 && b === 0 && p[2] === 0) ||
    (a === 198 && (b === 18 || b === 19)) ||
    a >= 224
  );
}

function ipv6Private(ip) {
  const h = ip.toLowerCase().replace(/^\[|\]$/g, '');
  if (h === '::' || h === '::1') return true;
  // IPv4 in IPv6 (::ffff:127.0.0.1 of ::ffff:7f00:1)
  const mapped = h.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return ipv4Private(mapped[1]);
  if (/^::ffff:/.test(h)) {
    const parts = h.slice(7).split(':');
    if (parts.length === 2) {
      const n = parts.map((x) => parseInt(x, 16));
      return ipv4Private(`${n[0] >> 8}.${n[0] & 255}.${n[1] >> 8}.${n[1] & 255}`);
    }
    return true;
  }
  return /^(fc|fd|fe[89ab]|ff)/.test(h) || /^::/.test(h) || /^64:ff9b:/.test(h) || /^2001:db8:/.test(h);
}

export function isPrivateAddress(host) {
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) return ipv4Private(host);
  if (host.includes(':')) return ipv6Private(host);
  return false;
}

// Geeft een URL terug als het adres veilig is om op te halen, anders null.
export function safeUrl(input) {
  let u;
  try {
    u = new URL(String(input ?? '').trim());
  } catch (_) {
    return null;
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
  if (u.username || u.password) return null;
  if (u.port && u.port !== '80' && u.port !== '443') return null;
  // De URL-parser schrijft 2130706433, 0x7f.1 en 127.1 al om naar 127.0.0.1
  const host = u.hostname.toLowerCase().replace(/\.$/, '');
  if (!host || host === 'localhost' || host.endsWith('.localhost')) return null;
  if (/\.(local|internal|lan|home|arpa|test|invalid)$/.test(host)) return null;
  if (host.startsWith('[') || host.includes(':')) return isPrivateAddress(host.replace(/^\[|\]$/g, '')) ? null : u;
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) return ipv4Private(host) ? null : u;
  // Een naam zonder punt is een naam in een intern netwerk
  if (!host.includes('.')) return null;
  return u;
}

// De naam opzoeken via DNS over HTTPS en weigeren als een antwoord in een privénetwerk ligt (een publieke naam die
// naar 127.0.0.1 wijst). Lukt het opzoeken niet, dan beslist fetch zelf (Workers kan geen privénetwerk bereiken).
export async function resolvesPrivate(host, fetcher = fetch) {
  if (isPrivateAddress(host)) return true;
  for (const type of ['A', 'AAAA']) {
    try {
      const r = await fetcher(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(host)}&type=${type}`, {
        headers: { Accept: 'application/dns-json' },
      });
      if (!r.ok) continue;
      const j = await r.json();
      for (const a of j?.Answer ?? []) {
        if ((a.type === 1 || a.type === 28) && isPrivateAddress(String(a.data))) return true;
      }
    } catch (_) {
      // verder
    }
  }
  return false;
}

// De pagina ophalen: elke doorverwijzing opnieuw nakijken, hoogstens MAX_PAGE_BYTES, met een tijdslimiet.
export async function fetchPage(url, fetcher = fetch) {
  let current = safeUrl(url);
  if (!current) return { error: 'bad_url' };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      if (await resolvesPrivate(current.hostname, fetcher)) return { error: 'bad_url' };
      const res = await fetcher(current.toString(), {
        redirect: 'manual',
        signal: controller.signal,
        headers: { 'User-Agent': USER_AGENT, Accept: 'text/html,application/xhtml+xml' },
      });
      if (res.status >= 300 && res.status < 400) {
        const loc = res.headers.get('Location');
        const next = loc ? safeUrl(new URL(loc, current).toString()) : null;
        if (!next) return { error: 'bad_url' };
        current = next;
        continue;
      }
      if (!res.ok) return { error: 'fetch_failed', status: res.status };
      const type = res.headers.get('Content-Type') ?? '';
      if (type && !/html|xml|text\/plain/i.test(type)) return { error: 'not_html' };
      const declared = Number(res.headers.get('Content-Length') ?? 0);
      if (declared > MAX_PAGE_BYTES) return { error: 'too_big' };
      const reader = res.body?.getReader();
      if (!reader) return { html: '', url: current.toString() };
      const chunks = [];
      let size = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > MAX_PAGE_BYTES) {
          await reader.cancel().catch(() => {});
          return { error: 'too_big' };
        }
        chunks.push(value);
      }
      const all = new Uint8Array(size);
      let at = 0;
      for (const c of chunks) {
        all.set(c, at);
        at += c.length;
      }
      return { html: new TextDecoder('utf-8', { fatal: false }).decode(all), url: current.toString() };
    }
    return { error: 'bad_url' };
  } catch (e) {
    return { error: controller.signal.aborted ? 'timeout' : 'fetch_failed' };
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Het recept uit de pagina lezen

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', frac12: '½', frac14: '¼', frac34: '¾', deg: '°' };

export function decodeEntities(s) {
  return String(s).replace(/&(#x[0-9a-f]+|#\d+|[a-z0-9]+);/gi, (m, e) => {
    if (e[0] === '#') {
      const code = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : m;
    }
    return ENTITIES[e.toLowerCase()] ?? m;
  });
}

function cleanLine(s, max = 200) {
  return decodeEntities(String(s).replace(/<[^>]*>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

// "4", "4 servings", ["4", "4 porties"], 4 → 4; niets bruikbaars → null
export function parseYield(v) {
  if (Array.isArray(v)) {
    for (const x of v) {
      const n = parseYield(x);
      if (n != null) return n;
    }
    return null;
  }
  if (typeof v === 'number') return v >= 1 && v <= 1000 ? Math.round(v) : null;
  if (typeof v !== 'string') return null;
  const m = v.match(/\d+(?:[.,]\d+)?/);
  if (!m) return null;
  const n = Math.round(Number(m[0].replace(',', '.')));
  return n >= 1 && n <= 1000 ? n : null;
}

function isRecipe(o) {
  const t = o?.['@type'];
  return t === 'Recipe' || (Array.isArray(t) && t.includes('Recipe')) || t === 'schema:Recipe';
}

function findRecipe(node, depth = 0) {
  if (!node || typeof node !== 'object' || depth > 6) return null;
  if (Array.isArray(node)) {
    for (const x of node) {
      const r = findRecipe(x, depth + 1);
      if (r) return r;
    }
    return null;
  }
  if (isRecipe(node)) return node;
  for (const k of ['@graph', 'mainEntity', 'mainEntityOfPage', 'itemListElement', 'item']) {
    const r = findRecipe(node[k], depth + 1);
    if (r) return r;
  }
  return null;
}

function imageOf(v) {
  if (!v) return null;
  if (typeof v === 'string') return v;
  if (Array.isArray(v)) return imageOf(v[0]);
  if (typeof v === 'object') return imageOf(v.url ?? v.contentUrl);
  return null;
}

export function cleanIngredients(list) {
  const out = [];
  const seen = new Set();
  for (const x of Array.isArray(list) ? list : typeof list === 'string' ? list.split(/\n+/) : []) {
    if (typeof x !== 'string') continue;
    const l = cleanLine(x);
    if (!l || seen.has(l.toLowerCase())) continue;
    seen.add(l.toLowerCase());
    out.push(l);
    if (out.length >= MAX_LINES) break;
  }
  return out;
}

// Het schema.org-recept uit de JSON-LD van een pagina. Geeft {name, servings, ingredients, image} of null.
export function parseJsonLd(html) {
  const re = /<script\b[^>]*type\s*=\s*["']?application\/ld\+json["']?[^>]*>([\s\S]*?)<\/script>/gi;
  for (const m of String(html).matchAll(re)) {
    let data;
    try {
      data = JSON.parse(m[1].trim().replace(/^<!\[CDATA\[|\]\]>$/g, ''));
    } catch (_) {
      continue;
    }
    const r = findRecipe(data);
    if (!r) continue;
    const ingredients = cleanIngredients(r.recipeIngredient ?? r.ingredients);
    if (!ingredients.length) continue;
    const image = imageOf(r.image);
    return {
      name: r.name ? cleanLine(r.name, 120) : null,
      servings: parseYield(r.recipeYield ?? r.yield),
      ingredients,
      image: image && /^https?:\/\//.test(image) ? image : null,
    };
  }
  return null;
}

// De zichtbare tekst van een pagina, ingekort voor het model.
export function visibleText(html, max = MAX_TEXT) {
  const title = String(html).match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] ?? '';
  const body = String(html)
    .replace(/<(script|style|noscript|svg|template|iframe|head|nav|footer)\b[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<(br|p|li|div|h[1-6]|tr)\b[^>]*>/gi, '\n')
    .replace(/<[^>]+>/g, ' ');
  const t = decodeEntities(`${title}\n${body}`)
    .split('\n')
    .map((l) => l.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .join('\n');
  return t.slice(0, max);
}

const TEXT_PROMPT = [
  'Below is the text of a recipe web page. Answer with strict JSON only, no other text:',
  '{"name": recipe title, "servings": number of servings or null, "ingredients": ["one ingredient line as written", ...]}',
  'Copy each ingredient line with its amount and unit as written. No steps, no comments.',
  'If the text has no recipe, answer {"ingredients": []}.',
].join('\n');

const PHOTO_PROMPT = [
  'This is a photo of a recipe (for example a cookbook page). Answer with strict JSON only, no other text:',
  '{"name": recipe title, "servings": number of servings or null, "ingredients": ["one ingredient line as written", ...]}',
  'Copy each ingredient line with its amount and unit as written. No steps, no comments.',
  'If there is no recipe in the photo, answer {"ingredients": []}.',
].join('\n');

// Het antwoord van het model nakijken: {name, servings, ingredients} of null als er geen ingrediënten zijn.
export function normaliseRecipe(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const ingredients = cleanIngredients(raw.ingredients ?? raw.recipeIngredient);
  if (!ingredients.length) return null;
  return {
    name: typeof raw.name === 'string' && raw.name.trim() ? cleanLine(raw.name, 120) : null,
    servings: parseYield(raw.servings ?? raw.recipeYield),
    ingredients,
    image: null,
  };
}

// ---------------------------------------------------------------------------------------------------------------

// Alleen met Pro: zonder teller (migratie niet uitgevoerd of storing) kan dat niet nagekeken worden.
export async function checkRecipeQuota(auth, fetcher = fetch) {
  const quota = await useAiQuota(auth, 'recipe', fetcher);
  if (!quota) return { error: json({ error: 'pro_required' }, 403) };
  if (!quota.allowed) {
    if (!quota.pro) return { error: json({ error: 'pro_required' }, 403) };
    return { error: json({ error: 'quota', used: quota.used, limit: quota.limit, pro: true }, 429) };
  }
  return { quota };
}

export async function onRequestPost({ request, env }) {
  const who = await checkLogin(request);
  if (who.error) return who.error;
  const type = request.headers.get('Content-Type') ?? '';

  const rate = await hourly('recipe', who.user, PER_HOUR);
  if (!rate.allowed) return json({ error: 'too_many' }, 429);

  // Foto van een kookboekpagina
  if (/^image\//i.test(type)) {
    if (!env.AI) return json({ error: 'not_configured' }, 503);
    const declared = Number(request.headers.get('Content-Length') ?? 0);
    if (declared > MAX_IMAGE_BYTES) return json({ error: 'too_big' }, 413);
    const photo = new Uint8Array(await request.arrayBuffer());
    if (photo.length > MAX_IMAGE_BYTES) return json({ error: 'too_big' }, 413);
    const mime = imageType(photo);
    if (!mime) return json({ error: 'bad_image' }, 400);
    const q = await checkRecipeQuota(who.auth);
    if (q.error) return q.error;
    await rate.count();
    try {
      const r = await env.AI.run(MODEL, {
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: PHOTO_PROMPT },
              { type: 'image_url', image_url: { url: dataUrl(photo, mime) } },
            ],
          },
        ],
        max_tokens: 900,
        temperature: 0,
      });
      const out = normaliseRecipe(modelObject(r));
      if (!out) return json({ error: 'no_recipe', quota: q.quota }, 422);
      return json({ ...out, source: 'photo', quota: q.quota });
    } catch (_) {
      return json({ error: 'failed' }, 502);
    }
  }

  // Link
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: 'bad_url' }, 400);
  }
  if (!safeUrl(body?.url)) return json({ error: 'bad_url' }, 400);
  const q = await checkRecipeQuota(who.auth);
  if (q.error) return q.error;
  await rate.count();

  const page = await fetchPage(body.url);
  if (page.error) return json({ error: page.error, quota: q.quota }, page.error === 'bad_url' ? 400 : 422);
  const fromLd = parseJsonLd(page.html);
  if (fromLd) return json({ ...fromLd, source: 'jsonld', url: page.url, quota: q.quota });

  // Geen JSON-LD: het tekstmodel leest de zichtbare tekst
  if (!env.AI) return json({ error: 'no_recipe', quota: q.quota }, 422);
  const text = visibleText(page.html);
  if (text.length < 80) return json({ error: 'no_recipe', quota: q.quota }, 422);
  try {
    const r = await env.AI.run(MODEL, {
      messages: [{ role: 'user', content: `${TEXT_PROMPT}\n\n---\n${text}` }],
      max_tokens: 900,
      temperature: 0,
    });
    const out = normaliseRecipe(modelObject(r));
    if (!out) return json({ error: 'no_recipe', quota: q.quota }, 422);
    return json({ ...out, source: 'ai', url: page.url, quota: q.quota });
  } catch (_) {
    return json({ error: 'failed' }, 502);
  }
}
