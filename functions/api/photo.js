// Cloudflare Pages Function: foto van een bord naar een zin voor "Snel loggen". De app stuurt een verkleinde JPEG
// (ongeveer 1024 px); een beeldmodel van Workers AI (binding "AI") noemt wat er op het bord ligt, met een geschatte
// hoeveelheid, in dezelfde vorm als een getypte zin ("150 g spaghetti bolognese, 1 slice of bread"). De app zoekt die
// zin daarna op zoals bij Snel loggen, zodat de gebruiker alles nakijkt voor er iets toegevoegd wordt.
// Alleen voor ingelogde gebruikers: het Supabase-token wordt eerst gecontroleerd. De foto wordt niet bewaard.
// Per account geldt een dagteller (3 gratis, 50 met Pro) in Supabase (photo_quota_use, migratie 20261026000000_pro).
// Is die er nog niet, dan werkt het zoals vroeger: alleen de rem per uur.

const SUPABASE_URL = 'https://hvqbqgxpksxmavopngap.supabase.co';
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2cWJxZ3hwa3N4bWF2b3BuZ2FwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNTk1ODAsImV4cCI6MjEwNzczNTU4MH0.SY50CM-HSMNYWOxidnFS8yjve46NdbmKhFwZDPPTI3g';
const MAX_BYTES = 1_500_000; // een JPEG van 1024 px aan kwaliteit 80 is meestal 100 à 300 kB
const PER_HOUR = 30;
// Llama 4 Scout: kan beelden lezen, vraagt geen aparte licentie-aanvaarding (zoals Llama 3.2 Vision) en is goedkoop
const MODEL = '@cf/meta/llama-4-scout-17b-16e-instruct';

const PROMPT = [
  'You look at a photo of a meal and list every food and drink you can see, with an estimated amount.',
  'Answer in English, on one line, as a comma-separated list, for example:',
  '150 g spaghetti bolognese, 1 slice of bread, 1 glass of orange juice',
  'Rules: use grams ("120 g rice") or a common portion ("1 apple", "2 eggs", "1 cup of coffee", "1 bowl of soup").',
  'Use plain food names that a nutrition database would know. Count separate items separately.',
  'No explanations, no totals, no calories, no extra text. If there is no food or drink in the photo, answer: none',
].join('\n');

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

// Het antwoord van het model opkuisen tot één zin voor de parser van Snel loggen.
function cleanSentence(raw) {
  let t = String(raw ?? '').trim();
  // Soms toch een inleiding ("Here is the list:") of opsomming op meerdere regels
  t = t.replace(/^[^\n:]*\b(here|list|photo|image|see)\b[^\n:]*:\s*/i, '');
  t = t
    .split(/\n+/)
    .map((l) => l.replace(/^\s*(?:[-*•]|\d+[.)])\s+/, '').trim())
    .filter(Boolean)
    .join(', ');
  t = t.replace(/\*\*/g, '').replace(/\s*,\s*(,\s*)+/g, ', ').replace(/[.\s]+$/, '').trim();
  if (/^none\b/i.test(t) || /^(no food|i (can't|cannot)|sorry)/i.test(t)) return '';
  return t.slice(0, 500);
}

// De dagteller verhogen met het token van de gebruiker zelf (auth.uid() in Supabase). Geeft {allowed, used, limit,
// pro} terug, of null als de teller niet beschikbaar is: de functie bestaat nog niet (PGRST202, migratie niet
// uitgevoerd) of Supabase antwoordt niet. Dan geldt alleen de rem per uur, zodat loggen met een foto niet stukgaat
// door een storing bij de teller.
export async function useQuota(auth, fetcher = fetch) {
  try {
    const r = await fetcher(`${SUPABASE_URL}/rest/v1/rpc/photo_quota_use`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: auth, 'Content-Type': 'application/json' },
      body: '{}',
    });
    if (!r.ok) {
      let code = '';
      try {
        code = (await r.json())?.code ?? '';
      } catch (_) {}
      if (code !== 'PGRST202') console.log(`photo_quota_use: ${r.status} ${code}`);
      return null;
    }
    const q = await r.json();
    if (typeof q?.allowed !== 'boolean') return null;
    return { allowed: q.allowed, used: Number(q.used) || 0, limit: Number(q.limit) || 0, pro: q.pro === true };
  } catch (e) {
    console.log(`photo_quota_use: ${e}`);
    return null;
  }
}

export async function onRequestPost({ request, env }) {
  if (!env.AI) return json({ error: 'not_configured' }, 503);
  const auth = request.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'login' }, 401);
  const who = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } });
  if (!who.ok) return json({ error: 'login' }, 401);
  const user = (await who.json()).id;

  // Eerst de grootte (via de header, zodat een te groot bestand niet eerst helemaal ingelezen wordt)
  const declared = Number(request.headers.get('Content-Length') ?? 0);
  if (declared > MAX_BYTES) return json({ error: 'too_big' }, 413);

  const photo = new Uint8Array(await request.arrayBuffer());
  if (photo.length > MAX_BYTES) return json({ error: 'too_big' }, 413);
  // Een JPEG begint met FF D8, een PNG met 89 50
  const jpeg = photo[0] === 0xff && photo[1] === 0xd8;
  const png = photo[0] === 0x89 && photo[1] === 0x50;
  if (photo.length < 1000 || (!jpeg && !png)) return json({ error: 'bad_image' }, 400);

  // Hoogstens 30 foto's per gebruiker per uur (teller in de cache van Cloudflare; bij benadering per datacenter).
  // Blijft als tweede rem naast de dagteller, en is de enige rem zolang de migratie er niet staat.
  const hour = Math.floor(Date.now() / 3_600_000);
  const key = new Request(`https://ratelimit.local/photo/${user}/${hour}`);
  const cache = caches.default;
  const seen = await cache.match(key);
  const count = seen ? Number(await seen.text()) : 0;
  if (count >= PER_HOUR) return json({ error: 'too_many' }, 429);

  // De dagteller pas na de controles hierboven, zodat een kapotte foto geen foto van vandaag kost
  const quota = await useQuota(auth);
  if (quota && !quota.allowed) return json({ error: 'quota', used: quota.used, limit: quota.limit, pro: quota.pro }, 429);
  await cache.put(key, new Response(String(count + 1), { headers: { 'Cache-Control': 'max-age=3600' } }));

  let b64 = '';
  for (let i = 0; i < photo.length; i += 0x8000) b64 += String.fromCharCode(...photo.subarray(i, i + 0x8000));
  try {
    const r = await env.AI.run(MODEL, {
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: PROMPT },
            { type: 'image_url', image_url: { url: `data:image/${png ? 'png' : 'jpeg'};base64,${btoa(b64)}` } },
          ],
        },
      ],
      max_tokens: 200,
      temperature: 0.2,
    });
    const body = { text: cleanSentence(r?.response) };
    // De app toont daarmee meteen "nog 1 van 3 gratis foto's vandaag", zonder extra vraag aan de server
    if (quota) body.quota = { used: quota.used, limit: quota.limit, pro: quota.pro };
    return json(body);
  } catch (e) {
    return json({ error: 'failed' }, 502);
  }
}
