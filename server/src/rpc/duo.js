// Duo: wie een Duo-abonnement koopt (duo_monthly of duo_yearly in Google Play), kiest één vriend die ook Supporter
// is zolang dat abonnement loopt. De partner krijgt een eigen rij in pro_status met source 'duo' (tot de vervaldatum
// van het abonnement), zodat alles wat naar Supporter kijkt (badge, randen, tellers, stemmen) gewoon werkt.
//
// Regels: de partner is een vriend, zit niet al in een andere Duo en is niet jezelf; de partner wijzigt hoogstens één
// keer per 30 dagen (ook weghalen telt), zodat Duo niet rondgedeeld wordt. Het abonnement zelf verlengen of stoppen
// (src/internal.js) en elke nacht (src/cron.js) zet de partner mee via syncDuoPartner.
import { endPro, extendPro } from '../pro.js';
import { DbError } from '../errors.js';
import { areFriends } from './shared.js';

export const DUO_PRODUCTS = ['duo_monthly', 'duo_yearly'];
const CHANGE_DAYS = 30;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Tot wanneer het Duo-abonnement van [owner] loopt (ISO), of null als er geen lopend is. */
export async function duoUntil(db, owner, now = new Date()) {
  const products = DUO_PRODUCTS.map(() => '?').join(', ');
  return db
    .prepare(`SELECT max(expiry) AS until FROM play_purchases WHERE user_id = ? AND product IN (${products}) AND expiry > ?`)
    .bind(owner, ...DUO_PRODUCTS, now.toISOString())
    .first('until');
}

/** De partner van [owner] gelijkzetten met diens Duo-abonnement: verlengen zolang het loopt, anders stopzetten. */
export async function syncDuoPartner(db, owner, now = new Date()) {
  const row = await db.prepare('SELECT partner FROM duo_members WHERE owner = ?').bind(owner).first();
  if (!row?.partner) return;
  const until = await duoUntil(db, owner, now);
  await db.batch([until ? extendPro(db, row.partner, until, 'duo', now) : endPro(db, row.partner, now.toISOString(), 'duo', now)]);
}

/** Elke nacht: alle partners gelijkzetten (ook als Google een melding niet stuurde). */
export async function syncAllDuos(db, now = new Date()) {
  const { results } = await db.prepare('SELECT owner FROM duo_members WHERE partner IS NOT NULL').all();
  for (const r of results) await syncDuoPartner(db, r.owner, now);
  return results.length;
}

const nameOf = (db, uid) => db.prepare('SELECT name, code FROM friend_profiles WHERE user_id = ?').bind(uid).first();

/** De Duo van de vrager: als koper (met partner) of als partner (met de koper). */
async function duo_status(ctx) {
  const { db, uid, now } = ctx;
  const own = await db.prepare('SELECT partner, changed_at FROM duo_members WHERE owner = ?').bind(uid).first();
  const until = await duoUntil(db, uid, now);
  if (until || own) {
    const partner = own?.partner ? { id: own.partner, ...((await nameOf(db, own.partner)) ?? { name: null, code: null }) } : null;
    const next = own ? new Date(Date.parse(own.changed_at) + CHANGE_DAYS * 86_400_000) : null;
    return {
      role: 'owner',
      active: !!until,
      until: until ?? null,
      partner,
      next_change: next && next > now ? next.toISOString() : null,
    };
  }
  const of = await db.prepare('SELECT owner FROM duo_members WHERE partner = ?').bind(uid).first();
  if (of) {
    return { role: 'partner', active: !!(await duoUntil(db, of.owner, now)), until: await duoUntil(db, of.owner, now), owner: { id: of.owner, name: (await nameOf(db, of.owner))?.name ?? null } };
  }
  return { role: null, active: false, until: null };
}

/**
 * Een vriend als partner kiezen (of wisselen). Antwoord { result, status }: result is ok, no_duo (geen lopend
 * Duo-abonnement), self, not_friends, taken (zit al in een Duo) of too_soon (pas na 30 dagen opnieuw wisselen).
 */
async function duo_set_partner(ctx, p) {
  const { db, uid, now } = ctx;
  const other = p.p_other;
  if (typeof other !== 'string' || !UUID.test(other)) throw new DbError('22P02', `invalid input syntax for type uuid: "${other}"`);
  const until = await duoUntil(db, uid, now);
  if (!until) return { result: 'no_duo', status: await duo_status(ctx) };
  if (other === uid) return { result: 'self', status: await duo_status(ctx) };
  if (!(await areFriends(db, uid, uid, other))) return { result: 'not_friends', status: await duo_status(ctx) };
  const own = await db.prepare('SELECT partner, changed_at FROM duo_members WHERE owner = ?').bind(uid).first();
  if (own?.partner === other) return { result: 'ok', status: await duo_status(ctx) };
  const taken = await db.prepare('SELECT 1 FROM duo_members WHERE partner = ? OR (owner = ? AND partner IS NOT NULL) LIMIT 1').bind(other, other).first();
  if (taken) return { result: 'taken', status: await duo_status(ctx) };
  if (own && Date.parse(own.changed_at) + CHANGE_DAYS * 86_400_000 > now.getTime()) return { result: 'too_soon', status: await duo_status(ctx) };
  const stmts = [];
  if (own?.partner) stmts.push(endPro(db, own.partner, now.toISOString(), 'duo', now));
  stmts.push(
    db
      .prepare('INSERT INTO duo_members (owner, partner, changed_at) VALUES (?, ?, ?) ON CONFLICT (owner) DO UPDATE SET partner = excluded.partner, changed_at = excluded.changed_at')
      .bind(uid, other, now.toISOString()),
    extendPro(db, other, until, 'duo', now),
  );
  try {
    await db.batch(stmts);
  } catch (e) {
    // Net tegelijk door iemand anders gekozen (UNIQUE op partner)
    if (/UNIQUE/i.test(String(e?.message))) return { result: 'taken', status: await duo_status(ctx) };
    throw e;
  }
  ctx.notify(other, { type: 'social' });
  if (own?.partner) ctx.notify(own.partner, { type: 'social' });
  return { result: 'ok', status: await duo_status(ctx) };
}

/** Als koper je partner weghalen (telt als wissel: de volgende kan pas na 30 dagen). */
async function duo_remove(ctx) {
  const { db, uid, now } = ctx;
  const own = await db.prepare('SELECT partner FROM duo_members WHERE owner = ?').bind(uid).first();
  if (!own?.partner) return await duo_status(ctx);
  await db.batch([
    endPro(db, own.partner, now.toISOString(), 'duo', now),
    db.prepare('UPDATE duo_members SET partner = NULL, changed_at = ? WHERE owner = ?').bind(now.toISOString(), uid),
  ]);
  ctx.notify(own.partner, { type: 'social' });
  return await duo_status(ctx);
}

/** Als partner uit een Duo stappen. */
async function duo_leave(ctx) {
  const { db, uid, now } = ctx;
  const of = await db.prepare('SELECT owner FROM duo_members WHERE partner = ?').bind(uid).first();
  if (!of) return await duo_status(ctx);
  await db.batch([
    endPro(db, uid, now.toISOString(), 'duo', now),
    db.prepare('UPDATE duo_members SET partner = NULL WHERE owner = ? AND partner = ?').bind(of.owner, uid),
  ]);
  ctx.notify(of.owner, { type: 'social' });
  return await duo_status(ctx);
}

export default { duo_status, duo_set_partner, duo_remove, duo_leave };
