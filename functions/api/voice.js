// Cloudflare Pages Function: spraak naar tekst voor "Snel loggen" op toestellen zonder eigen spraakherkenning
// (bv. GrapheneOS). De app stuurt een korte WAV-opname; Whisper (Workers AI, binding "AI") maakt er tekst van.
// Alleen voor ingelogde gebruikers: het Supabase-token wordt eerst gecontroleerd. De opname wordt niet bewaard.
// Dagteller ai_quota_use('voice'): 60 per dag, 200 met Pro (migratie 20261107000000_quota_voice_off). Daarnaast een
// rem per uur. Zonder die migratie (PGRST202 of onbekende soort) alleen de rem per uur; bij een storing van de teller
// geen opname (503).

import { checkLogin, hourly, json, useQuotaOrHourly } from '../_lib/ai.js';
import { readBytes } from '../_lib/body.js';

const MAX_BYTES = 1_500_000; // ongeveer 45 s WAV aan 16 kHz mono
const PER_HOUR = 60;

export async function onRequestPost({ request, env }, fetcher = fetch) {
  if (!env.AI) return json({ error: 'not_configured' }, 503);
  const who = await checkLogin(request, fetcher);
  if (who.error) return who.error;

  // Hoogstens 60 opnames per gebruiker per uur (teller in de cache van Cloudflare; bij benadering per datacenter)
  const rate = await hourly('voice', who.user, PER_HOUR);
  if (!rate.allowed) return json({ error: 'too_many' }, 429);

  const read = await readBytes(request, MAX_BYTES, { error: 'too_long' });
  if (read.error) return read.error;
  if (read.bad) return json({ error: 'failed' }, 400);
  const audio = read.bytes;
  if (audio.length < 1000) return json({ text: '' });
  const lang = (new URL(request.url).searchParams.get('lang') ?? 'en').slice(0, 2);

  // De dagteller pas na de controles hierboven, zodat een lege opname niets kost (in één stap in de database, dus
  // ook veilig bij veel verzoeken tegelijk)
  const q = await useQuotaOrHourly(who.auth, 'voice', rate, fetcher, () => ({ error: 'too_many' }));
  if (q.error) return q.error;

  let b64 = '';
  for (let i = 0; i < audio.length; i += 0x8000) b64 += String.fromCharCode(...audio.subarray(i, i + 0x8000));
  try {
    const r = await env.AI.run('@cf/openai/whisper-large-v3-turbo', { audio: btoa(b64), language: lang, task: 'transcribe', vad_filter: true });
    return json({ text: (r?.text ?? '').trim() });
  } catch (e) {
    return json({ error: 'failed' }, 502);
  }
}
