// Cloudflare Pages Function: spraak naar tekst voor "Snel loggen" op toestellen zonder eigen spraakherkenning
// (bv. GrapheneOS). De app stuurt een korte WAV-opname; Whisper (Workers AI, binding "AI") maakt er tekst van.
// Alleen voor ingelogde gebruikers: het Supabase-token wordt eerst gecontroleerd. De opname wordt niet bewaard.

const SUPABASE_URL = 'https://hvqbqgxpksxmavopngap.supabase.co';
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2cWJxZ3hwa3N4bWF2b3BuZ2FwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNTk1ODAsImV4cCI6MjEwNzczNTU4MH0.SY50CM-HSMNYWOxidnFS8yjve46NdbmKhFwZDPPTI3g';
const MAX_BYTES = 1_500_000; // ongeveer 45 s WAV aan 16 kHz mono

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

export async function onRequestPost({ request, env }) {
  if (!env.AI) return json({ error: 'not_configured' }, 503);
  const auth = request.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'login' }, 401);
  const who = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } });
  if (!who.ok) return json({ error: 'login' }, 401);
  const user = (await who.json()).id;

  // Hoogstens 60 opnames per gebruiker per uur (teller in de cache van Cloudflare; bij benadering per datacenter)
  const hour = Math.floor(Date.now() / 3_600_000);
  const key = new Request(`https://ratelimit.local/voice/${user}/${hour}`);
  const cache = caches.default;
  const seen = await cache.match(key);
  const count = seen ? Number(await seen.text()) : 0;
  if (count >= 60) return json({ error: 'too_many' }, 429);
  await cache.put(key, new Response(String(count + 1), { headers: { 'Cache-Control': 'max-age=3600' } }));

  const audio = new Uint8Array(await request.arrayBuffer());
  if (audio.length < 1000) return json({ text: '' });
  if (audio.length > MAX_BYTES) return json({ error: 'too_long' }, 413);
  const lang = (new URL(request.url).searchParams.get('lang') ?? 'en').slice(0, 2);

  let b64 = '';
  for (let i = 0; i < audio.length; i += 0x8000) b64 += String.fromCharCode(...audio.subarray(i, i + 0x8000));
  try {
    const r = await env.AI.run('@cf/openai/whisper-large-v3-turbo', { audio: btoa(b64), language: lang, task: 'transcribe', vad_filter: true });
    return json({ text: (r?.text ?? '').trim() });
  } catch (e) {
    return json({ error: 'failed' }, 502);
  }
}
