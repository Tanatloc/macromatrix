// Cloudflare Pages Function: de app meldt een aankoop in Google Play (een Pro-abonnement). We kijken ze na bij Google
// (subscriptionsv2), koppelen ze aan het ingelogde account en zetten Pro aan tot de vervaldatum. De app bevestigt de
// aankoop pas bij de winkel (completePurchase) als dit {ok:true} geeft; we bevestigen hier zelf ook.
//
// Vraag: POST met Authorization: Bearer <Supabase-token> en {purchaseToken, productId, packageName}.
// Antwoord: {ok:true, until} of {ok:false, reason}. reason: not_configured (secrets ontbreken, 503), login (401),
// too_many (429), bad_request, package, product, invalid, pending, expired, other_account (al gekoppeld aan een
// ander account) of failed.
//
// Secrets (Cloudflare Pages, project voedingsapp): GOOGLE_PLAY_SA (JSON-sleutel van het serviceaccount) en
// SUPABASE_SERVICE_ROLE_KEY. Uitleg: voedingsapp-data/playstore/PLAYSTORE.md, "Google Play Billing instellen".

import { checkLogin, hourly, json } from '../_lib/ai.js';
import { PACKAGE } from '../_lib/google.js';
import { applyPurchase, playConfig, PRODUCTS } from '../_lib/play.js';

// Ruim genoeg voor herstellen op een paar toestellen; houdt misbruik van de Google-API tegen
const PER_HOUR = 30;

export async function verify(request, env, fetcher = fetch, now = Date.now()) {
  const cfg = playConfig(env);
  if (!cfg) return json({ ok: false, reason: 'not_configured' }, 503);
  const login = await checkLogin(request, fetcher);
  if (login.error) return json({ ok: false, reason: 'login' }, login.error.status);

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ ok: false, reason: 'bad_request' }, 400);
  }
  const token = body?.purchaseToken;
  if (typeof token !== 'string' || token.length < 10 || token.length > 4096) return json({ ok: false, reason: 'bad_request' }, 400);
  if (!PRODUCTS.includes(body?.productId)) return json({ ok: false, reason: 'product' }, 400);
  if (body.packageName != null && body.packageName !== PACKAGE) return json({ ok: false, reason: 'package' }, 400);

  const rate = await hourly('play-verify', login.user, PER_HOUR);
  if (!rate.allowed) return json({ ok: false, reason: 'too_many' }, 429);
  await rate.count();

  const r = await applyPurchase(cfg, { token, user: login.user }, fetcher, now);
  if (r.ok) return json({ ok: true, until: r.until });
  return json({ ok: false, reason: r.reason }, r.status);
}

export const onRequestPost = ({ request, env }) => verify(request, env);
