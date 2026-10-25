// Cloudflare Pages Function: realtime-meldingen van Google Play (Real-time developer notifications), via een
// Pub/Sub-pushabonnement op https://macromatrix.eu/api/play-rtdn?secret=<PLAY_RTDN_SECRET>.
//
// Bij elke melding over een abonnement (verlengd, opgezegd, terugbetaald, afgelopen, ...) kijken we dat abonnement
// opnieuw na bij Google en werken we pro_status bij voor het gekoppelde account, ook als de app niet geopend wordt.
// Een melding is alleen een seintje: wat telt, is wat Google zelf over het abonnement zegt.
//
// Antwoord 200 = verwerkt (of bewust genegeerd: een test, een ander pakket, een aankoop die de app nog niet meldde);
// Pub/Sub probeert alleen bij een fout (502) later opnieuw.
//
// Secrets: PLAY_RTDN_SECRET, GOOGLE_PLAY_SA en SUPABASE_SERVICE_ROLE_KEY.

import { json } from '../_lib/ai.js';
import { readJson } from '../_lib/body.js';
import { PACKAGE } from '../_lib/google.js';
import { applyPurchase, playConfig } from '../_lib/play.js';

// Twee teksten vergelijken zonder dat de duur verraadt hoeveel tekens kloppen.
export function sameSecret(a, b) {
  const x = new TextEncoder().encode(String(a ?? ''));
  const y = new TextEncoder().encode(String(b ?? ''));
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

// Het bericht van Pub/Sub uitpakken: {message: {data: base64(JSON)}}. Geeft het JSON-object van Google of null.
export function decodeNotification(body) {
  const data = body?.message?.data;
  if (typeof data !== 'string' || data.length > 20000) return null;
  try {
    const raw = atob(data.replace(/-/g, '+').replace(/_/g, '/'));
    const bytes = Uint8Array.from(raw, (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch (_) {
    return null;
  }
}

// Een bericht van Pub/Sub is klein (data hoogstens 20000 tekens, zie decodeNotification)
const MAX_BODY = 64_000;

export async function rtdn(request, env, fetcher = fetch, now = Date.now()) {
  const cfg = playConfig(env);
  if (!cfg || !env?.PLAY_RTDN_SECRET) return json({ ok: false, reason: 'not_configured' }, 503);
  const secret = new URL(request.url).searchParams.get('secret');
  if (!secret || !sameSecret(secret, env.PLAY_RTDN_SECRET)) return json({ ok: false, reason: 'forbidden' }, 403);

  // Te groot of kapot: bewust genegeerd (200), want opnieuw proberen maakt het bericht niet beter
  const read = await readJson(request, MAX_BODY);
  if (read.error || read.bad) return json({ ok: true, ignored: 'bad_message' });
  const body = read.value;
  const n = decodeNotification(body);
  if (!n || n.packageName !== PACKAGE) return json({ ok: true, ignored: 'other' });
  // Een abonnement dat verandert, of een terugbetaling (productType 1 = abonnement)
  const token =
    n.subscriptionNotification?.purchaseToken ??
    (Number(n.voidedPurchaseNotification?.productType) === 1 ? n.voidedPurchaseNotification?.purchaseToken : null);
  if (typeof token !== 'string' || !token) return json({ ok: true, ignored: n.testNotification ? 'test' : 'other' });

  const r = await applyPurchase(cfg, { token, user: null }, fetcher, now);
  if (r.reason === 'failed') return json({ ok: false, reason: 'failed' }, 502);
  return json(r.ok ? { ok: true, until: r.until } : { ok: true, result: r.reason });
}

export const onRequestPost = ({ request, env }) => rtdn(request, env);
