// De functies die de app (en onze Pages Functions) aanroepen, zoals de RPC's in Supabase: POST /v1/rpc/<naam>
// met dezelfde parameters (p_…) en hetzelfde antwoord als PostgREST gaf.
//
// Contract voor elke functie: async (ctx, params) => JSON-waarde.
//   ctx.db   D1 (env.DB)            ctx.uid  ingelogde gebruiker (null bij handler.anon)
//   ctx.env  bindings en variabelen  ctx.now  Date van dit verzoek
//   ctx.notify(uid, bericht)  seintje naar de toestellen van een gebruiker (UserHub), mislukt nooit
// Fouten: raise('melding') zoals `raise exception` (P0001), of new DbError(code, melding).
// Autorisatie: RLS bestaat niet in D1. Elke query filtert zelf op ctx.uid; wat een ander mag zien, staat expliciet
// in de functie (zoals de security-definer-functies in Supabase).
import { DbError, raise } from '../errors.js';
import { hubFor } from '../hub.js';
import challenges from './challenges.js';
import duo from './duo.js';
import misc from './misc.js';
import { textBlocked } from './shared.js';
import social from './social.js';

const isMonday = (d) => /^\d{4}-\d{2}-\d{2}$/.test(d) && new Date(`${d}T00:00:00Z`).getUTCDay() === 1;
const int = (v, name) => {
  if (!Number.isInteger(v)) throw new DbError('22P02', `invalid input syntax for type integer: "${v}" (${name})`);
  return v;
};

const core = {
  /** Voor /api/off-contribute: staat er een scheldwoord in? */
  async text_blocked(_ctx, p) {
    return textBlocked(p.p);
  },

  /** Account en alles wat erbij hoort weg (ON DELETE CASCADE), en de live verbindingen dicht. */
  async delete_account(ctx) {
    await ctx.db.prepare('DELETE FROM "user" WHERE id = ?').bind(ctx.uid).run();
    try {
      await hubFor(ctx.env, ctx.uid).closeAll();
    } catch {}
    return null;
  },

  /** Was in Supabase een upsert op weekly_scores (RLS: alleen je eigen rij). */
  async weekly_score_put(ctx, p) {
    if (!isMonday(p.p_week)) raise('week moet een maandag zijn', '23514');
    const points = p.p_points == null ? null : int(p.p_points, 'p_points');
    const mid = p.p_mid_points == null ? null : int(p.p_mid_points, 'p_mid_points');
    await ctx.db
      .prepare(
        `INSERT INTO weekly_scores (user_id, week, score, days, points, mid_points, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (user_id, week) DO UPDATE SET score = excluded.score, days = excluded.days, points = excluded.points,
           mid_points = excluded.mid_points, updated_at = excluded.updated_at`,
      )
      .bind(ctx.uid, p.p_week, int(p.p_score, 'p_score'), int(p.p_days, 'p_days'), points, mid, ctx.now.toISOString())
      .run();
    return null;
  },

  /** Was in Supabase een delete op weekly_scores (RLS: alleen je eigen rij). */
  async weekly_score_delete(ctx, p) {
    await ctx.db.prepare('DELETE FROM weekly_scores WHERE user_id = ? AND week = ?').bind(ctx.uid, String(p.p_week ?? '')).run();
    return null;
  },
};

export const RPC = { ...core, ...social, ...challenges, ...misc, ...duo };

/** Eén functie uitvoeren. [uid] is null zonder sessie; alleen functies met .anon mogen dat. */
export async function callRpc(name, params, { db, env, uid, now = new Date(), waitUntil = () => {} }) {
  const fn = Object.hasOwn(RPC, name) ? RPC[name] : null;
  if (!fn) throw new DbError('PGRST202', `Could not find the function public.${name}`, { status: 404 });
  if (!uid && !fn.anon) throw new DbError('PGRST301', 'not logged in', { status: 401 });
  if (params !== null && (typeof params !== 'object' || Array.isArray(params))) throw new DbError('22P02', 'parameters must be an object');
  const ctx = {
    db,
    env,
    uid,
    now,
    notify: (to, message) => {
      try {
        waitUntil(hubFor(env, to).notify(message).catch(() => {}));
      } catch {
        // Zonder HUB-binding (tests): niets te melden
      }
    },
  };
  return fn(ctx, params ?? {});
}
