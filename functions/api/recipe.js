// Cloudflare Pages Function: een recept importeren uit een link of uit een foto van een kookboekpagina (alleen Pro).
//
// Link: de app stuurt {"url": "..."}. Deze functie haalt de pagina zelf op (alleen http/https, geen adressen in een
// privénetwerk of op deze machine, hoogstens 2 MB en 10 s) en leest het schema.org-recept (JSON-LD:
// recipeIngredient, recipeYield, name, image). Staat dat er niet, dan leest het tekstmodel de zichtbare tekst.
// Foto: de app stuurt een verkleinde JPEG (Content-Type image/jpeg); het beeldmodel leest titel, porties en
// ingrediënten.
// Antwoord: {name, servings, ingredients: [regels], image, source}. De app zoekt elke regel op zoals bij Snel loggen.
// Niets wordt bewaard. Dagteller ai_quota_use('recipe'): gratis 0, met Pro 20 per dag (migratie
// 20261027000000_ai_quota). Zonder die teller kan Pro niet nagekeken worden: dan pro_required. Voor een link wordt
// eerst alleen de stand gelezen (ai_quota) en pas geteld als de pagina opgehaald is.

import { MODEL, MAX_IMAGE_BYTES, aiQuotaStatus, checkLogin, dataUrl, hourly, imageType, json, modelObject } from '../_lib/ai.js';
import { readBytes, readJson } from '../_lib/body.js';

const PER_HOUR = 20;
const MAX_PAGE_BYTES = 2_000_000;
const FETCH_TIMEOUT_MS = 10_000;
const MAX_REDIRECTS = 3;
const MAX_TEXT = 12_000;
const MAX_LINES = 60;
// {"url": "..."}: ruim genoeg voor een lange link
const MAX_LINK_BODY = 16_000;

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

// Een IPv6-adres als 8 getallen van 16 bits (ook met :: en met een IPv4-adres achteraan), of null als het geen
// geldig adres is.
export function ipv6Groups(ip) {
  let h = ip.toLowerCase().replace(/^\[|\]$/g, '');
  const zone = h.indexOf('%');
  if (zone >= 0) h = h.slice(0, zone);
  const v4 = h.match(/^(.*:)(\d+\.\d+\.\d+\.\d+)$/);
  if (v4) {
    const p = v4[2].split('.').map(Number);
    if (p.some((n) => n > 255)) return null;
    h = `${v4[1]}${((p[0] << 8) | p[1]).toString(16)}:${((p[2] << 8) | p[3]).toString(16)}`;
  }
  const halves = h.split('::');
  if (halves.length > 2) return null;
  const part = (x) => (x === '' ? [] : x.split(':'));
  const head = part(halves[0]);
  const tail = halves.length === 2 ? part(halves[1]) : [];
  const fill = 8 - head.length - tail.length;
  if (halves.length === 2 ? fill < 1 : fill !== 0) return null;
  const all = [...head, ...Array(halves.length === 2 ? fill : 0).fill('0'), ...tail];
  if (all.some((g) => !/^[0-9a-f]{1,4}$/.test(g))) return null;
  return all.map((g) => parseInt(g, 16));
}

const v4of = (hi, lo) => `${hi >> 8}.${hi & 255}.${lo >> 8}.${lo & 255}`;

function ipv6Private(ip) {
  const g = ipv6Groups(ip);
  if (!g) return true;
  // ::ffff:a.b.c.d (IPv4 in IPv6): de regels voor IPv4
  if (g.slice(0, 5).every((n) => n === 0) && g[5] === 0xffff) return ipv4Private(v4of(g[6], g[7]));
  // ::, ::1, ::a.b.c.d en alles in 0::/16
  if (g[0] === 0) return true;
  // 6to4 (2002::/16): het IPv4-adres zit in de volgende 32 bits
  if (g[0] === 0x2002) return ipv4Private(v4of(g[1], g[2]));
  return (
    (g[0] === 0x2001 && g[1] === 0) || // Teredo (2001::/32)
    (g[0] === 0x2001 && g[1] === 0xdb8) || // documentatie
    (g[0] === 0x64 && g[1] === 0xff9b) || // NAT64
    g[0] === 0x100 || // weggooien (100::/64)
    (g[0] & 0xfe00) === 0xfc00 || // uniek lokaal (fc00::/7)
    (g[0] & 0xff80) === 0xfe80 || // link-local en site-local (fe80::/10, fec0::/10)
    (g[0] & 0xff00) === 0xff00 // multicast
  );
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
// naar 127.0.0.1 wijst). Lukt het opzoeken niet (geen antwoord, of een DNS-fout anders dan "bestaat niet"), dan telt
// de naam ook als privé: liever een recept niet importeren dan blind een adres ophalen.
export async function resolvesPrivate(host, fetcher = fetch) {
  if (isPrivateAddress(host)) return true;
  for (const type of ['A', 'AAAA']) {
    try {
      const r = await fetcher(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(host)}&type=${type}`, {
        headers: { Accept: 'application/dns-json' },
      });
      if (!r.ok) return true;
      const j = await r.json();
      // Status 0 = goed, 3 = bestaat niet (dan faalt het ophalen zelf); de rest (bv. 2 = SERVFAIL) is een fout
      if (j?.Status != null && j.Status !== 0 && j.Status !== 3) return true;
      for (const a of j?.Answer ?? []) {
        if ((a.type === 1 || a.type === 28) && isPrivateAddress(String(a.data))) return true;
      }
    } catch (_) {
      return true;
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

// Zonder regexen die bij een vijandige pagina kwadratisch worden (veel "<" zonder ">", veel "<nav" zonder "</nav>"):
// alles hieronder zoekt met indexOf of met een vaste regex vanaf een positie, en komt elk stuk tekst maar één keer
// voorbij.

// Elke tag (<...>) vervangen: [repl] krijgt de tag en geeft de vervanging. Een "<" zonder ">" erna blijft staan.
export function replaceTags(s, repl) {
  let out = '';
  let at = 0;
  for (;;) {
    const lt = s.indexOf('<', at);
    if (lt < 0) break;
    const gt = s.indexOf('>', lt + 1);
    if (gt < 0) break;
    // Zoals <[^>]+>: minstens één teken ertussen; "<>" is geen tag
    if (gt === lt + 1) {
      out += s.slice(at, gt + 1);
      at = gt + 1;
      continue;
    }
    out += s.slice(at, lt) + repl(s.slice(lt, gt + 1));
    at = gt + 1;
  }
  return out + s.slice(at);
}

// Blokken zoals <nav ...>...</nav> weglaten (vervangen door een spatie). Een blok zonder einde blijft staan; per
// soort wordt maar één keer tot het einde gezocht naar een sluittag die er niet is.
export function dropBlocks(s, tags) {
  const open = new RegExp(`<(${tags.join('|')})\\b`, 'gi');
  const noEnd = new Set();
  let out = '';
  let at = 0;
  for (;;) {
    open.lastIndex = at;
    const m = open.exec(s);
    if (!m) break;
    const tag = m[1].toLowerCase();
    let end = -1;
    if (!noEnd.has(tag)) {
      const close = new RegExp(`</${tag}>`, 'gi');
      close.lastIndex = m.index + m[0].length;
      const c = close.exec(s);
      end = c ? c.index + c[0].length : -1;
      if (end < 0) noEnd.add(tag);
    }
    if (end < 0) {
      out += s.slice(at, m.index + m[0].length);
      at = m.index + m[0].length;
      continue;
    }
    out += `${s.slice(at, m.index)} `;
    at = end;
  }
  return out + s.slice(at);
}

// <!-- ... --> weglaten (een spatie); een opmerking zonder einde blijft staan.
function dropComments(s) {
  let out = '';
  let at = 0;
  for (;;) {
    const open = s.indexOf('<!--', at);
    if (open < 0) break;
    const close = s.indexOf('-->', open + 4);
    if (close < 0) break;
    out += `${s.slice(at, open)} `;
    at = close + 3;
  }
  return out + s.slice(at);
}

// Tags die een nieuwe regel beginnen (<p ...>, <br>, <li>, ...) vervangen door een regeleinde.
function lineBreaks(s) {
  const open = /<(br|p|li|div|h[1-6]|tr)\b/gi;
  let out = '';
  let at = 0;
  for (;;) {
    open.lastIndex = at;
    const m = open.exec(s);
    if (!m) break;
    const gt = s.indexOf('>', m.index);
    if (gt < 0) break;
    out += `${s.slice(at, m.index)}\n`;
    at = gt + 1;
  }
  return out + s.slice(at);
}

function cleanLine(s, max = 200) {
  // Een regel is kort; een enorme "regel" eerst inkorten (ruim, want tags en entiteiten vallen nog weg)
  return decodeEntities(replaceTags(String(s).slice(0, max * 20), () => ' '))
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
  const s = String(html);
  const open = /<script\b/gi;
  const close = /<\/script>/gi;
  let at = 0;
  for (;;) {
    open.lastIndex = at;
    const m = open.exec(s);
    if (!m) break;
    const gt = s.indexOf('>', m.index);
    if (gt < 0) break;
    close.lastIndex = gt + 1;
    const c = close.exec(s);
    if (!c) break;
    at = c.index + c[0].length;
    if (!/type\s*=\s*["']?application\/ld\+json/i.test(s.slice(m.index, gt))) continue;
    let data;
    try {
      data = JSON.parse(s.slice(gt + 1, c.index).trim().replace(/^<!\[CDATA\[|\]\]>$/g, ''));
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
const HIDDEN = ['script', 'style', 'noscript', 'svg', 'template', 'iframe', 'head', 'nav', 'footer'];

// De tekst van de eerste <title>, of ''.
function titleOf(s) {
  const open = /<title/i.exec(s);
  if (!open) return '';
  const gt = s.indexOf('>', open.index);
  if (gt < 0) return '';
  const close = /<\/title>/gi;
  close.lastIndex = gt + 1;
  const c = close.exec(s);
  return c ? s.slice(gt + 1, c.index) : '';
}

export function visibleText(html, max = MAX_TEXT) {
  const s = String(html);
  const title = titleOf(s);
  // In dezelfde volgorde als vroeger: blokken, opmerkingen, regeleindes, en dan alle andere tags
  const body = replaceTags(lineBreaks(dropComments(dropBlocks(s, HIDDEN))), () => ' ');
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
// [peek] = alleen de stand lezen (ai_quota), zonder te tellen: voor een link wordt pas geteld als de pagina opgehaald
// is, zodat een link die niet werkt geen import van vandaag kost.
export async function checkRecipeQuota(auth, fetcher = fetch, peek = false) {
  const quota = (await aiQuotaStatus(auth, 'recipe', fetcher, peek ? 'ai_quota' : 'ai_quota_use')).quota ?? null;
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
    const read = await readBytes(request, MAX_IMAGE_BYTES);
    if (read.error) return read.error;
    if (read.bad) return json({ error: 'bad_image' }, 400);
    const photo = read.bytes;
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
  const read = await readJson(request, MAX_LINK_BODY);
  if (read.error) return read.error;
  const body = read.value;
  if (read.bad || !safeUrl(body?.url)) return json({ error: 'bad_url' }, 400);
  // Eerst alleen kijken of het mag (Pro en nog niet op), zodat gratis accounts geen pagina's laten ophalen
  const peek = await checkRecipeQuota(who.auth, undefined, true);
  if (peek.error) return peek.error;
  await rate.count();

  const page = await fetchPage(body.url);
  if (page.error) return json({ error: page.error, quota: peek.quota }, page.error === 'bad_url' ? 400 : 422);
  // Pas nu tellen (in één stap in de database): een link die niet opengaat, kost niets
  const q = await checkRecipeQuota(who.auth);
  if (q.error) return q.error;
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
