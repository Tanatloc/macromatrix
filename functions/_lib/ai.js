// Gedeelde stukken voor de AI-functies (/api/label, /api/recipe, /api/off-contribute): inloggen nakijken, de rem per
// uur, foto's nakijken en de dagteller ai_quota_use (migratie 20261027000000_ai_quota). Dit bestand heeft geen
// onRequest-functies en wordt dus geen eigen adres op de site.

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
// nog mag; count() telt er één bij, pas als alle andere controles goed zijn.
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

// De dagteller voor een soort (label of recipe) verhogen met het token van de gebruiker zelf (auth.uid()).
// Geeft {allowed, used, limit, pro} terug, of null als de teller niet beschikbaar is: de functie bestaat nog niet
// (PGRST202, migratie niet uitgevoerd) of Supabase antwoordt niet. Wat null betekent, beslist de functie zelf:
// /api/label werkt dan verder (alleen de rem per uur), /api/recipe weigert (Pro kan niet nagekeken worden).
export async function useAiQuota(auth, kind, fetcher = fetch) {
  try {
    const r = await fetcher(`${SUPABASE_URL}/rest/v1/rpc/ai_quota_use`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_kind: kind }),
    });
    if (!r.ok) {
      let code = '';
      try {
        code = (await r.json())?.code ?? '';
      } catch (_) {}
      if (code !== 'PGRST202') console.log(`ai_quota_use(${kind}): ${r.status} ${code}`);
      return null;
    }
    const q = await r.json();
    if (typeof q?.allowed !== 'boolean') return null;
    return { allowed: q.allowed, used: Number(q.used) || 0, limit: Number(q.limit) || 0, pro: q.pro === true };
  } catch (e) {
    console.log(`ai_quota_use(${kind}): ${e}`);
    return null;
  }
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
  const resp = r?.response;
  if (resp && typeof resp === 'object') return resp;
  return firstJsonObject(resp);
}
