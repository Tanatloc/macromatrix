// Live meldingen: de app vraagt (ingelogd) een kort ticket en opent daarmee een WebSocket naar zijn UserHub.
// Een ticket is uid.vervaltijd.HMAC (60 s geldig), zodat het sessietoken nooit in een URL staat.
import { hubFor } from './hub.js';

const enc = new TextEncoder();
const b64url = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function key(env) {
  return crypto.subtle.importKey('raw', enc.encode(`live:${env.BETTER_AUTH_SECRET}`), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}

export async function makeTicket(env, uid, now = Date.now()) {
  const body = `${uid}.${now + 60_000}`;
  return `${body}.${b64url(await crypto.subtle.sign('HMAC', await key(env), enc.encode(body)))}`;
}

/** Geeft de uid als het ticket klopt en nog geldig is, anders null. */
export async function checkTicket(env, ticket, now = Date.now()) {
  const parts = String(ticket ?? '').split('.');
  if (parts.length !== 3) return null;
  const [uid, exp, sig] = parts;
  if (!(Number(exp) > now)) return null;
  const expected = b64url(await crypto.subtle.sign('HMAC', await key(env), enc.encode(`${uid}.${exp}`)));
  if (expected.length !== sig.length) return null;
  let diff = 0;
  for (let i = 0; i < sig.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  return diff === 0 ? uid : null;
}

/** Melding naar alle toestellen van een gebruiker; fouten worden genegeerd (het is maar een seintje). */
export async function notifyUser(env, uid, message) {
  try {
    await hubFor(env, uid).notify(message);
  } catch (e) {
    console.warn('hub-melding mislukt', e?.message ?? e);
  }
}
