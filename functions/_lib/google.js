// Inloggen bij Google met een serviceaccount (de JSON-sleutel in het secret GOOGLE_PLAY_SA) en de Google Play
// Developer API voor abonnementen. Alles met WebCrypto, zonder bibliotheken: een JWT met RS256 ondertekenen en die
// inwisselen voor een toegangstoken. Dit bestand heeft geen onRequest-functies en wordt dus geen eigen adres.
//
// Nooit tokens of sleutels loggen: foutmeldingen bevatten alleen een statuscode.

export const PACKAGE = 'eu.macromatrix.app';
export const PLAY_SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
const PLAY_API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}/purchases`;

const enc = new TextEncoder();

export function base64url(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : enc.encode(String(bytes));
  let s = '';
  for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000));
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----" naar de ruwe PKCS#8-bytes.
export function pemToPkcs8(pem) {
  const b64 = String(pem ?? '')
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '')
    .replace(/\\n/g, '')
    .replace(/\s+/g, '');
  const raw = atob(b64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

// De JSON-sleutel van het serviceaccount lezen. Geeft null als ze ontbreekt of onbruikbaar is.
export function parseServiceAccount(raw) {
  if (!raw) return null;
  try {
    const sa = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (typeof sa?.client_email !== 'string' || typeof sa?.private_key !== 'string') return null;
    return sa;
  } catch (_) {
    return null;
  }
}

// Een JWT met RS256 ondertekenen met de sleutel van het serviceaccount.
export async function signJwt(sa, scope, now = Date.now()) {
  const iat = Math.floor(now / 1000);
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT', ...(sa.private_key_id ? { kid: sa.private_key_id } : {}) }));
  const claims = base64url(
    JSON.stringify({ iss: sa.client_email, scope, aud: sa.token_uri || 'https://oauth2.googleapis.com/token', iat, exp: iat + 3600 }),
  );
  const key = await crypto.subtle.importKey('pkcs8', pemToPkcs8(sa.private_key), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, [
    'sign',
  ]);
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(`${header}.${claims}`)));
  return `${header}.${claims}.${base64url(sig)}`;
}

// Het toegangstoken blijft bewaard zolang deze worker leeft (een uur geldig; we vernieuwen 5 minuten vooraf).
let cached = null;
export function clearGoogleTokenCache() {
  cached = null;
}

export class GoogleError extends Error {
  constructor(status, where) {
    super(`google ${where}: ${status}`);
    this.status = status;
  }
}

export async function googleAccessToken(sa, fetcher = fetch, now = Date.now()) {
  if (cached && cached.email === sa.client_email && cached.exp > now + 300_000) return cached.token;
  const assertion = await signJwt(sa, PLAY_SCOPE, now);
  const r = await fetcher(sa.token_uri || 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${assertion}`,
  });
  if (!r.ok) throw new GoogleError(r.status, 'token');
  const j = await r.json();
  if (typeof j?.access_token !== 'string') throw new GoogleError(502, 'token');
  cached = { email: sa.client_email, token: j.access_token, exp: now + (Number(j.expires_in) || 3600) * 1000 };
  return cached.token;
}

// Een abonnement opvragen (subscriptionsv2). Geeft het object van Google terug, null als Google het token niet kent
// (400, 404 of 410), en gooit een GoogleError bij andere fouten.
export async function getSubscription(purchaseToken, accessToken, fetcher = fetch) {
  const r = await fetcher(`${PLAY_API}/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (r.status === 400 || r.status === 404 || r.status === 410) return null;
  if (!r.ok) throw new GoogleError(r.status, 'subscriptionsv2');
  return r.json();
}

// Een abonnement bevestigen, zodat Google het na 3 dagen niet terugbetaalt. Een fout is niet erg: de app bevestigt
// ook (completePurchase), en de volgende controle probeert opnieuw.
export async function acknowledgeSubscription(productId, purchaseToken, accessToken, fetcher = fetch) {
  try {
    const r = await fetcher(
      `${PLAY_API}/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`,
      { method: 'POST', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: '{}' },
    );
    if (!r.ok) console.log(`play acknowledge: ${r.status}`);
    return r.ok;
  } catch (e) {
    console.log('play acknowledge: failed');
    return false;
  }
}
