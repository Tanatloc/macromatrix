// Gedeelde stukken voor de AI-functies (/api/label, /api/recipe, /api/off-contribute, /api/coach, /api/voice):
// inloggen nakijken, de rem per uur, foto's nakijken en de dagteller ai_quota_use (migratie 20261027000000_ai_quota).
// Dit bestand heeft geen onRequest-functies en wordt dus geen eigen adres op de site.

export const SUPABASE_URL = 'https://hvqbqgxpksxmavopngap.supabase.co';
export const ANON =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2cWJxZ3hwa3N4bWF2b3BuZ2FwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNTk1ODAsImV4cCI6MjEwNzczNTU4MH0.SY50CM-HSMNYWOxidnFS8yjve46NdbmKhFwZDPPTI3g';

// Zelfde beeldmodel als /api/photo: leest beelden, geen aparte licentie-aanvaarding, goedkoop
export const MODEL = '@cf/meta/llama-4-scout-17b-16e-instruct';

export const MAX_IMAGE_BYTES = 1_500_000;

export const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

// Het Supabase-token nakijken. Geeft {user, auth} terug, of een antwoord met error login.
export async function checkLogin(request, fetcher = fetch) {
  const auth = request.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return { error: json({ error: 'login' }, 401) };
  try {
    const who = await fetcher(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } });
    if (!who.ok) return { error: json({ error: 'login' }, 401) };
    const id = (await who.json())?.id;
    if (!id) return { error: json({ error: 'login' }, 401) };
    return { user: id, auth };
  } catch (_) {
    return { error: json({ error: 'failed' }, 502) };
  }
}

// Rem per gebruiker per uur (teller in de cache van Cloudflare; bij benadering per datacenter). check() zegt of het
// nog mag; count() telt er één bij, pas als alle andere controles goed zijn. Lezen en schrijven zijn twee stappen, dus
// veel verzoeken tegelijk lezen allemaal dezelfde stand: alleen een tweede rem naast de dagteller in de database.
export async function hourly(name, user, max) {
  const hour = Math.floor(Date.now() / 3_600_000);
  const key = new Request(`https://ratelimit.local/${name}/${user}/${hour}`);
  const cache = caches.default;
  const seen = await cache.match(key);
  const n = seen ? Number(await seen.text()) : 0;
  return {
    allowed: n < max,
    count: () => cache.put(key, new Response(String(n + 1), { headers: { 'Cache-Control': 'max-age=3600' } })),
  };
}

// Een JPEG (FF D8) of PNG (89 50) van een redelijke grootte. Geeft het mime-type terug, of null.
export function imageType(bytes) {
  if (!bytes || bytes.length < 1000 || bytes.length > MAX_IMAGE_BYTES) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return 'image/jpeg';
  if (bytes[0] === 0x89 && bytes[1] === 0x50) return 'image/png';
  return null;
}

export function dataUrl(bytes, mime) {
  let b64 = '';
  for (let i = 0; i < bytes.length; i += 0x8000) b64 += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return `data:${mime};base64,${btoa(b64)}`;
}

// De dagteller voor een soort (label, recipe, coach, voice of off) verhogen met het token van de gebruiker zelf
// (auth.uid()). Geeft {quota: {allowed, used, limit, pro}} terug, {missing: true} als de functie of de soort nog niet
// bestaat (PGRST202, of "onbekende soort" van een oudere migratie), of {down: true} als Supabase niet (goed)
// antwoordt. Een storing is nooit hetzelfde als een ontbrekende migratie: wie een teller nodig heeft, weigert dan.
// [rpc] = 'ai_quota' leest de stand zonder iets te verhogen (voor /api/recipe vóór het ophalen van de pagina).
export async function aiQuotaStatus(auth, kind, fetcher = fetch, rpc = 'ai_quota_use') {
  try {
    const r = await fetcher(`${SUPABASE_URL}/rest/v1/rpc/${rpc}`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_kind: kind }),
    });
    if (!r.ok) {
      let err = null;
      try {
        err = await r.json();
      } catch (_) {}
      const code = err?.code ?? '';
      if (code === 'PGRST202') return { missing: true };
      // Een database met een oudere migratie kent de soort niet: ook dan ontbreekt de migratie
      if (code === 'P0001' && /onbekende soort/.test(String(err?.message ?? ''))) return { missing: true };
      console.log(`${rpc}(${kind}): ${r.status} ${code}`);
      return { down: true };
    }
    const q = await r.json();
    if (typeof q?.allowed !== 'boolean') return { down: true };
    return { quota: { allowed: q.allowed, used: Number(q.used) || 0, limit: Number(q.limit) || 0, pro: q.pro === true } };
  } catch (e) {
    console.log(`${rpc}(${kind}): ${e}`);
    return { down: true };
  }
}

// Antwoord als de dagteller niet antwoordt: liever even niets dan onbeperkt (rekenkracht en schrijven kosten echt).
export const quotaDown = () => json({ error: 'unavailable' }, 503);

// De dagteller voor [kind], met de rem per uur als terugval zolang de migratie ontbreekt (alleen PGRST202 of een
// onbekende soort). [rate] = hourly(...) van de functie zelf. Geeft {quota} (of {quota: null} zonder teller), of
// {error: antwoord}: 429 quota/too_many als het op is, 503 bij een storing. Telt de rem per uur er één bij.
export async function useQuotaOrHourly(auth, kind, rate, fetcher = fetch, overLimit = (q) => ({ error: 'quota', used: q.used, limit: q.limit, pro: q.pro })) {
  const q = await aiQuotaStatus(auth, kind, fetcher);
  if (q.down) return { error: quotaDown() };
  if (q.quota && !q.quota.allowed) return { error: json(overLimit(q.quota), 429) };
  if (!rate.allowed) return { error: json({ error: 'too_many' }, 429) };
  await rate.count();
  return { quota: q.quota ?? null };
}

export class TimeoutError extends Error {}

// Een belofte met een tijdslimiet: na [ms] een TimeoutError (het model zelf loopt dan nog door, maar het antwoord
// telt niet meer).
export function withTimeout(promise, ms) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new TimeoutError(`na ${ms} ms`)), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}

// Markdown uit een zin van een model halen: **vet**, _schuin_, `code`, koppen, opsommingstekens en [links](...).
export function stripMarkdown(raw) {
  return String(raw ?? '')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/^\s{0,3}#{1,6}\s+/gm, '')
    .replace(/^\s*(?:[-*•+]|\d+[.)])\s+/gm, '')
    .replace(/(\*\*|__|\*|`+|~~)/g, '')
    .replace(/(^|\s)_([^_\s][^_]*)_(?=\s|[.,!?;:]|$)/g, '$1$2')
    .replace(/\s+/g, ' ')
    .trim();
}

// Het eerste JSON-object uit het antwoord van een model halen (soms met ```json eromheen of een inleiding).
export function firstJsonObject(raw) {
  const t = String(raw ?? '');
  const start = t.indexOf('{');
  if (start < 0) return null;
  let depth = 0;
  let inString = false;
  for (let i = start; i < t.length; i++) {
    const c = t[i];
    if (inString) {
      if (c === '\\') i++;
      else if (c === '"') inString = false;
    } else if (c === '"') inString = true;
    else if (c === '{') depth++;
    else if (c === '}' && --depth === 0) {
      try {
        return JSON.parse(t.slice(start, i + 1));
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

// Workers AI geeft soms al een object terug in plaats van tekst
export function modelObject(r) {
  // Sommige modellen (bv. gpt-oss) antwoorden in het chatformaat: de tekst staat dan in choices[0].message.content
  const resp = r?.response ?? r?.choices?.[0]?.message?.content;
  if (resp && typeof resp === 'object') return resp;
  return firstJsonObject(resp);
}
