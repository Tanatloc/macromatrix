// Live meldingen: de app vraagt (ingelogd) een kort ticket en opent daarmee een WebSocket naar zijn UserHub.
// Een ticket is uid.sessie-id.vervaltijd.HMAC (60 s geldig), zodat het sessietoken nooit in een URL staat. De sessie
// moet bij het verbinden nog bestaan, en uitloggen sluit de verbindingen van die sessie (hub.closeSession).
import { hubFor } from './hub.js';

const enc = new TextEncoder();
const b64url = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function key(env) {
  // Zonder geheim zou iedereen een ticket kunnen maken
  if (!env.BETTER_AUTH_SECRET || env.BETTER_AUTH_SECRET.length < 32) throw new Error('BETTER_AUTH_SECRET ontbreekt of is te kort');
  return crypto.subtle.importKey('raw', enc.encode(`live:${env.BETTER_AUTH_SECRET}`), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}

export async function makeTicket(env, uid, sid, now = Date.now()) {
  const body = `${uid}.${sid}.${now + 60_000}`;
  return `${body}.${b64url(await crypto.subtle.sign('HMAC', await key(env), enc.encode(body)))}`;
}

/** Geeft { uid, sid } als het ticket klopt, nog geldig is en de sessie nog bestaat, anders null. */
export async function checkTicket(env, ticket, now = Date.now()) {
  const parts = String(ticket ?? '').split('.');
  if (parts.length !== 4) return null;
  const [uid, sid, exp, sig] = parts;
  if (!(Number(exp) > now)) return null;
  const expected = b64url(await crypto.subtle.sign('HMAC', await key(env), enc.encode(`${uid}.${sid}.${exp}`)));
  if (expected.length !== sig.length) return null;
  let diff = 0;
  for (let i = 0; i < sig.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  if (diff !== 0) return null;
  const live = await env.DB.prepare('SELECT 1 FROM session WHERE id = ? AND "userId" = ? AND "expiresAt" > ?').bind(sid, uid, new Date(now).toISOString()).first();
  return live ? { uid, sid } : null;
}

/** Een client-id van de app (willekeurig per app-instantie), of null als die ontbreekt of niet klopt. */
export const clientId = (v) => (typeof v === 'string' && /^[A-Za-z0-9_-]{8,64}$/.test(v) ? v : null);

/**
 * Melding naar alle toestellen van een gebruiker, behalve client [except]; fouten worden genegeerd (het is maar een
 * seintje).
 */
export async function notifyUser(env, uid, message, except = null) {
  try {
    await hubFor(env, uid).notify(message, except);
  } catch (e) {
    console.warn('hub-melding mislukt', e?.message ?? e);
  }
}
