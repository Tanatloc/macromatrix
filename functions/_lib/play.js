// Gedeeld voor /api/play-verify (de app meldt een aankoop) en /api/play-rtdn (Google meldt een verandering): een
// abonnement bij Google nakijken, het aan één account koppelen (play_purchases) en pro_status bijwerken.
// Migratie: 20261102000000_play_billing.sql. Dit bestand heeft geen onRequest-functies en wordt dus geen eigen adres.
//
// pro_status en play_purchases worden geschreven met de service-role (secret SUPABASE_SERVICE_ROLE_KEY); de app kan
// daar zelf niets in zetten. Een langere Pro (bv. levenslang met de hand, 9999-12-31) wordt nooit ingekort, en bij
// een terugbetaling of einde raken we alleen een status aan die van Google Play komt (source 'play').

import { SUPABASE_URL } from './ai.js';
import { acknowledgeSubscription, getSubscription, GoogleError, googleAccessToken, parseServiceAccount } from './google.js';

// Moeten gelijk zijn aan de product-id's in de Play Console en in lib/sync/purchase.dart (ProPlan.productId)
export const PRODUCTS = ['pro_monthly', 'pro_yearly'];

// Toestanden waarin je betaald hebt (CANCELED = opgezegd, maar betaald tot de vervaldatum)
const ENTITLED = new Set(['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED']);

// De secrets voor Google en Supabase, of null als er een ontbreekt.
export function playConfig(env) {
  const sa = parseServiceAccount(env?.GOOGLE_PLAY_SA);
  const key = env?.SUPABASE_SERVICE_ROLE_KEY;
  if (!sa || typeof key !== 'string' || !key) return null;
  return { sa, key };
}

// Een antwoord van subscriptionsv2 beoordelen. Geeft {entitled, until (ms of null), product, reason}:
// reason is null als het goed is, anders 'product' (geen product van ons), 'pending' (betaling nog bezig) of
// 'expired' (afgelopen, terugbetaald, gepauzeerd of in de wacht).
export function evaluateSubscription(sub, now = Date.now()) {
  const items = (Array.isArray(sub?.lineItems) ? sub.lineItems : []).filter((li) => PRODUCTS.includes(li?.productId));
  if (!items.length) return { entitled: false, until: null, product: null, reason: 'product' };
  // De laatste vervaldatum telt (tijdens de respijtperiode schuift Google die al op)
  let until = null;
  let product = items[0].productId;
  for (const li of items) {
    const t = Date.parse(li.expiryTime ?? '');
    if (Number.isFinite(t) && (until === null || t > until)) {
      until = t;
      product = li.productId;
    }
  }
  const state = sub?.subscriptionState;
  if (state === 'SUBSCRIPTION_STATE_PENDING') return { entitled: false, until, product, reason: 'pending' };
  const entitled = ENTITLED.has(state) && until !== null && until > now;
  return { entitled, until, product, reason: entitled ? null : 'expired' };
}

// Zelfde als in de app (lib/sync/play_purchase.dart, accountHash): sha256 van de gebruikers-id, als hex. Gaat als
// obfuscatedAccountId mee naar Google, zodat een aankoop alleen bij het account hoort dat ze deed.
export async function accountHash(user) {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(String(user))));
  return [...d].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// --- Supabase met de service-role

function headers(key, extra = {}) {
  const h = { apikey: key, 'Content-Type': 'application/json', ...extra };
  // Een oude service_role-sleutel is een JWT en hoort ook in Authorization; een nieuwe sb_secret_-sleutel niet
  if (key.startsWith('eyJ')) h.Authorization = `Bearer ${key}`;
  return h;
}

export class SupabaseError extends Error {
  constructor(status, where) {
    super(`supabase ${where}: ${status}`);
    this.status = status;
  }
}

async function rest(cfg, fetcher, path, init = {}, where = path.split('?')[0]) {
  const r = await fetcher(`${SUPABASE_URL}/rest/v1/${path}`, { ...init, headers: headers(cfg.key, init.headers) });
  if (!r.ok) throw new SupabaseError(r.status, where);
  const t = await r.text();
  return t ? JSON.parse(t) : null;
}

const eq = (v) => `eq.${encodeURIComponent(v)}`;

export async function findPurchase(cfg, token, fetcher = fetch) {
  const rows = await rest(cfg, fetcher, `play_purchases?purchase_token=${eq(token)}&select=user_id,product,expiry`);
  return Array.isArray(rows) && rows.length ? rows[0] : null;
}

async function savePurchase(cfg, row, fetcher) {
  await rest(cfg, fetcher, 'play_purchases?on_conflict=purchase_token', {
    method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify(row),
  });
}

// Pro verlengen tot [untilIso], maar nooit inkorten. Eerst alleen bijwerken als de huidige rij korter loopt (één
// stap, dus ook veilig als er tegelijk met de hand iets toegekend wordt); is er nog geen rij, dan een nieuwe.
export async function grantPro(cfg, user, untilIso, fetcher = fetch) {
  const now = new Date().toISOString();
  const changed = await rest(cfg, fetcher, `pro_status?user_id=${eq(user)}&until=lt.${encodeURIComponent(untilIso)}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify({ until: untilIso, source: 'play', updated_at: now }),
  });
  if (Array.isArray(changed) && changed.length) return;
  // Geen rij, of een die al langer loopt: bij een bestaande rij doet dit niets
  await rest(cfg, fetcher, 'pro_status?on_conflict=user_id', {
    method: 'POST',
    headers: { Prefer: 'resolution=ignore-duplicates,return=minimal' },
    body: JSON.stringify({ user_id: user, until: untilIso, source: 'play', updated_at: now }),
  });
}

// Pro stopzetten na een einde of terugbetaling: tot nu, of tot de vervaldatum van een ander lopend Play-abonnement
// van hetzelfde account (bv. de nieuwe aankoop na een wissel van maand naar jaar). Alleen een rij met source 'play':
// Pro met de hand, als geschenk of via het web blijft staan.
export async function revokePro(cfg, user, exceptToken, fetcher = fetch, now = Date.now()) {
  const nowIso = new Date(now).toISOString();
  const others = await rest(
    cfg,
    fetcher,
    `play_purchases?user_id=${eq(user)}&purchase_token=neq.${encodeURIComponent(exceptToken)}&expiry=gt.${encodeURIComponent(nowIso)}&select=expiry&order=expiry.desc&limit=1`,
  );
  const floor = Array.isArray(others) && others.length ? new Date(others[0].expiry).toISOString() : nowIso;
  await rest(cfg, fetcher, `pro_status?user_id=${eq(user)}&source=eq.play&until=gt.${encodeURIComponent(floor)}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ until: floor, updated_at: nowIso }),
  });
}

// Een aankoop nakijken bij Google en verwerken.
// [user] = de ingelogde gebruiker (vanuit de app), of null (een melding van Google: dan de gekoppelde gebruiker).
// Geeft {ok:true, until} of {ok:false, reason, status}; reason: invalid, product, pending, expired, other_account,
// unknown (melding voor een aankoop die de app nog niet meldde) of failed.
export async function applyPurchase(cfg, { token, user = null }, fetcher = fetch, now = Date.now()) {
  try {
    const access = await googleAccessToken(cfg.sa, fetcher, now);
    const sub = await getSubscription(token, access, fetcher);
    if (!sub) return { ok: false, reason: 'invalid', status: 400 };
    const ev = evaluateSubscription(sub, now);
    if (ev.reason === 'product') return { ok: false, reason: 'product', status: 400 };

    // Bij wie hoort deze aankoop? Een wissel van abonnement of een nieuw abonnement na het opzeggen
    // (linkedPurchaseToken) hoort bij hetzelfde account als de vorige aankoop.
    const existing = await findPurchase(cfg, token, fetcher);
    const linkedToken = typeof sub.linkedPurchaseToken === 'string' && sub.linkedPurchaseToken ? sub.linkedPurchaseToken : null;
    const linked = !existing && linkedToken ? await findPurchase(cfg, linkedToken, fetcher) : null;
    const owner = existing?.user_id ?? linked?.user_id ?? null;
    if (user) {
      if (owner && owner !== user) return { ok: false, reason: 'other_account', status: 409 };
      const tag = sub.externalAccountIdentifiers?.obfuscatedExternalAccountId;
      if (tag && tag !== (await accountHash(user))) return { ok: false, reason: 'other_account', status: 409 };
    } else if (!owner) {
      return { ok: false, reason: 'unknown', status: 200 };
    }
    const uid = user ?? owner;

    if (ev.entitled || existing) {
      const expiry = ev.until !== null ? Math.min(ev.until, ev.entitled ? ev.until : now) : now;
      await savePurchase(
        cfg,
        {
          purchase_token: token,
          user_id: uid,
          product: ev.product,
          linked_purchase_token: linkedToken,
          expiry: new Date(expiry).toISOString(),
          updated_at: new Date(now).toISOString(),
        },
        fetcher,
      );
    }

    if (!ev.entitled) {
      if (ev.reason === 'expired' && existing) await revokePro(cfg, uid, token, fetcher, now);
      return { ok: false, reason: ev.reason, status: 200 };
    }

    // Ook hier bevestigen: zo wordt een aankoop nooit terugbetaald omdat de app halverwege stopte
    if (sub.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING') await acknowledgeSubscription(ev.product, token, access, fetcher);
    const until = new Date(ev.until).toISOString();
    await grantPro(cfg, uid, until, fetcher);
    return { ok: true, until };
  } catch (e) {
    // Alleen de soort fout en de status: nooit het token of de sleutel
    if (e instanceof GoogleError || e instanceof SupabaseError) console.log(`play: ${e.message}`);
    else console.log(`play: ${e?.name ?? 'error'}`);
    return { ok: false, reason: 'failed', status: 502 };
  }
}
