// Dagtellers (AI en foto's), Supporter (pro_status), vroege toegang (features), de roadmap, meldingen over
// uitdagingen (notify_tokens) en meldingen over AI-antwoorden (ai_reports). Vertaald uit de security-definer-functies
// in Supabase: dezelfde controles, meldingen en antwoorden.
// Een "dag" voor de tellers is de UTC-datum, zoals (now() at time zone 'utc')::date daar.
import { DbError, raise } from '../errors.js';
import { proActive } from './shared.js';

const AI_KINDS = ['label', 'recipe', 'coach', 'voice', 'off'];
const REPORT_KINDS = ['coach', 'photo', 'label', 'recipe', 'voice', 'other'];
const FRAMES = ['glow', 'orbit', 'sparkle', 'laurel', 'ripple', 'spin', 'sunburst', 'crown', 'wings', 'blades', 'royal'];
const DAY_MS = 86_400_000;

/** UTC-datum 'YYYY-MM-DD' van [now], eventueel [days] dagen verschoven. */
const utcDay = (now, days = 0) => new Date(now.getTime() + days * DAY_MS).toISOString().slice(0, 10);

/** Een tekstparameter zoals PostgREST hem doorgeeft (null blijft null). */
const text = (v) => (v == null ? null : typeof v === 'object' ? JSON.stringify(v) : String(v));

/** Zoals de cast naar boolean in Postgres: true/false, ook 't', 'yes', 'on', '1' en zo. */
function bool(v) {
  if (v == null || typeof v === 'boolean') return v ?? null;
  const s = String(v).trim().toLowerCase();
  if (['t', 'true', 'y', 'yes', 'on', '1'].includes(s)) return true;
  if (['f', 'false', 'n', 'no', 'off', '0'].includes(s)) return false;
  throw new DbError('22P02', `invalid input syntax for type boolean: "${v}"`);
}

/** Zoals de cast naar uuid: met of zonder streepjes, hoofdletters mogen; altijd terug als kleine letters met streepjes. */
function uuid(v) {
  if (v == null) return null;
  const h = String(v).trim().replace(/^\{(.*)\}$/, '$1').toLowerCase();
  const m = /^([0-9a-f]{8})-?([0-9a-f]{4})-?([0-9a-f]{4})-?([0-9a-f]{4})-?([0-9a-f]{12})$/.exec(h);
  if (!m) throw new DbError('22P02', `invalid input syntax for type uuid: "${v}"`);
  return m.slice(1).join('-');
}

/** left(btrim(s), n): btrim haalt alleen spaties weg; left telt tekens, geen UTF-16-eenheden. */
const trimLeft = (s, n) => [...String(s ?? '').replace(/^ +| +$/g, '')].slice(0, n).join('');

/**
 * Hoeveel AI-verzoeken per dag (ai_limit). De coach is gratis 2 keer per week (zie aiWeekly) zodra hij voor iedereen
 * open is, met Supporter 3 keer per dag.
 */
async function aiLimit(db, kind, pro, now) {
  switch (kind) {
    case 'label':
      return pro ? 30 : 1;
    case 'recipe':
      return pro ? 20 : 0;
    case 'coach':
      if (pro) return 3;
      return (await db.prepare("SELECT 1 FROM features WHERE id = 'coach' AND public_from <= ?").bind(now.toISOString()).first()) ? 2 : 0;
    case 'voice':
      return pro ? 200 : 60;
    case 'off':
      return 10;
    default:
      return 0;
  }
}

/** Hoeveel foto's per dag (photo_limit). */
const photoLimit = (pro) => (pro ? 50 : 3);

/**
 * Teller verhogen als hij nog onder [lim] zit, in één upsert: twee verzoeken tegelijk kunnen samen niet over de
 * grens. In dezelfde batch de stand lezen (voor als het niet mocht) en dagen ouder dan een week opruimen.
 */
async function bump(db, table, keyCols, keyVals, lim, today, uid) {
  const where = keyCols.map((c) => `${c} = ?`).join(' AND ');
  const [up, cur] = await db.batch([
    db
      .prepare(
        `INSERT INTO ${table} (${keyCols.join(', ')}, count) VALUES (${keyCols.map(() => '?').join(', ')}, 1)
         ON CONFLICT (${keyCols.join(', ')}) DO UPDATE SET count = ${table}.count + 1 WHERE ${table}.count < ? RETURNING count`,
      )
      .bind(...keyVals, lim),
    db.prepare(`SELECT count FROM ${table} WHERE ${where}`).bind(...keyVals),
    db.prepare(`DELETE FROM ${table} WHERE user_id = ? AND day < ?`).bind(uid, today.old),
  ]);
  const row = up.results[0];
  return row ? { allowed: true, used: row.count } : { allowed: false, used: cur.results[0]?.count ?? 0 };
}

const days = (now) => ({ day: utcDay(now), old: utcDay(now, -7) });

/** De coach zonder Supporter telt per week: de rij heeft dan de maandag (UTC) als dag. Al het andere telt per dag. */
const aiWeekly = (kind, pro) => kind === 'coach' && !pro;
const aiPeriod = (kind, pro, now) => (aiWeekly(kind, pro) ? utcDay(now, -((now.getUTCDay() + 6) % 7)) : utcDay(now));

/** Stand van de dagteller voor een AI-soort, zonder iets te verhogen. */
async function ai_quota(ctx, p) {
  const kind = text(p.p_kind);
  const pro = await proActive(ctx.db, ctx.uid, ctx.now);
  const lim = await aiLimit(ctx.db, kind, pro, ctx.now);
  const r = await ctx.db.prepare('SELECT count FROM ai_usage WHERE user_id = ? AND kind = ? AND day = ?').bind(ctx.uid, kind, aiPeriod(kind, pro, ctx.now)).first();
  const used = r?.count ?? 0;
  return { allowed: used < lim, used, limit: lim, pro, per: aiWeekly(kind, pro) ? 'week' : 'day' };
}

/** Eén AI-verzoek tellen (door /api/label, /api/coach, …). allowed false = op voor vandaag (of deze week, zie aiWeekly). */
async function ai_quota_use(ctx, p) {
  const kind = text(p.p_kind);
  if (kind == null || !AI_KINDS.includes(kind)) raise('onbekende soort');
  const pro = await proActive(ctx.db, ctx.uid, ctx.now);
  const lim = await aiLimit(ctx.db, kind, pro, ctx.now);
  const per = aiWeekly(kind, pro) ? 'week' : 'day';
  if (lim <= 0) return { allowed: false, used: 0, limit: lim, pro, per };
  // Opruimen blijft op een week: de maandag van deze week is nooit ouder dan zes dagen
  const d = { ...days(ctx.now), day: aiPeriod(kind, pro, ctx.now) };
  const r = await bump(ctx.db, 'ai_usage', ['user_id', 'kind', 'day'], [ctx.uid, kind, d.day], lim, d, ctx.uid);
  return { ...r, limit: lim, pro, per };
}

/** Stand van de fototeller. */
async function photo_quota(ctx) {
  const pro = await proActive(ctx.db, ctx.uid, ctx.now);
  const lim = photoLimit(pro);
  const r = await ctx.db.prepare('SELECT count FROM photo_usage WHERE user_id = ? AND day = ?').bind(ctx.uid, utcDay(ctx.now)).first();
  const used = r?.count ?? 0;
  return { allowed: used < lim, used, limit: lim, pro };
}

/** Eén foto tellen (door /api/photo). */
async function photo_quota_use(ctx) {
  const pro = await proActive(ctx.db, ctx.uid, ctx.now);
  const lim = photoLimit(pro);
  const d = days(ctx.now);
  const r = await bump(ctx.db, 'photo_usage', ['user_id', 'day'], [ctx.uid, d.day], lim, d, ctx.uid);
  return { ...r, limit: lim, pro };
}

/** Een fout AI-antwoord melden. Hoogstens 20 per dag (laatste 24 uur); de grens zit in de insert zelf. */
async function ai_report(ctx, p) {
  const kind = text(p.p_kind);
  const t = trimLeft(text(p.p_text), 4000);
  const n = trimLeft(text(p.p_note), 1000) || null;
  if (kind == null || !REPORT_KINDS.includes(kind)) return 'bad_kind';
  if (t === '') return 'empty';
  const at = ctx.now.toISOString();
  const r = await ctx.db
    .prepare(
      `INSERT INTO ai_reports (id, reporter, kind, text, note, created_at) SELECT ?, ?, ?, ?, ?, ?
       WHERE (SELECT count(*) FROM ai_reports WHERE reporter = ? AND created_at > ?) < 20 RETURNING id`,
    )
    .bind(crypto.randomUUID(), ctx.uid, kind, t, n, at, ctx.uid, new Date(ctx.now.getTime() - DAY_MS).toISOString())
    .first();
  return r ? 'reported' : 'limit';
}

/** Je eigen Supporter-status (of de standaard als je er nooit een had). */
async function my_pro(ctx) {
  const s = await ctx.db.prepare('SELECT until, source, show_badge, frame FROM pro_status WHERE user_id = ?').bind(ctx.uid).first();
  if (!s) return { pro: false, until: null, source: null, show_badge: true, frame: null };
  return { pro: s.until > ctx.now.toISOString(), until: s.until, source: s.source, show_badge: s.show_badge === 1, frame: s.frame };
}

/** Het Supporter-badge tonen of verbergen (null = tonen). */
async function pro_show_badge(ctx, p) {
  const show = bool(p.p_show) ?? true;
  await ctx.db.prepare('UPDATE pro_status SET show_badge = ?, updated_at = ? WHERE user_id = ?').bind(show ? 1 : 0, ctx.now.toISOString(), ctx.uid).run();
  return null;
}

/** Een rand rond je avatar kiezen (null = geen). Alleen met een lopend abonnement; true als het gelukt is. */
async function pro_set_frame(ctx, p) {
  const frame = text(p.p_frame);
  if (frame != null && !FRAMES.includes(frame)) raise('onbekende rand');
  const now = ctx.now.toISOString();
  const r = await ctx.db.prepare('UPDATE pro_status SET frame = ?, updated_at = ? WHERE user_id = ? AND until > ?').bind(frame, now, ctx.uid, now).run();
  return r.meta.changes > 0;
}

/** Alle functies met hun vensters: enabled = voor iedereen open, of al vroeg open en jij bent Supporter. */
async function my_features(ctx) {
  const now = ctx.now.toISOString();
  const pro = await proActive(ctx.db, ctx.uid, ctx.now);
  const { results } = await ctx.db.prepare('SELECT id, title_en, title_nl, early_from, public_from FROM features ORDER BY id').all();
  return results.map((f) => {
    const open = f.public_from != null && f.public_from <= now;
    const early = f.early_from != null && f.early_from <= now;
    return { ...f, enabled: open || (early && pro), early: early && !open };
  });
}

/** De roadmap: alleen stemmen van wie nu Supporter is tellen mee; mine = jij stemde. */
async function roadmap_list(ctx) {
  const { results } = await ctx.db
    .prepare(
      `SELECT i.id, i.title_en, i.title_nl, i.desc_en, i.desc_nl, i.status, i.sort,
         (SELECT count(*) FROM roadmap_votes v JOIN pro_status s ON s.user_id = v.user_id AND s.until > ? WHERE v.item_id = i.id) AS votes,
         EXISTS (SELECT 1 FROM roadmap_votes v WHERE v.item_id = i.id AND v.user_id = ?) AS mine
       FROM roadmap_items i
       ORDER BY CASE i.status WHEN 'building' THEN 0 WHEN 'planned' THEN 1 WHEN 'idea' THEN 2 WHEN 'early' THEN 3 ELSE 4 END,
         i.sort, i.created_at`,
    )
    .bind(ctx.now.toISOString(), ctx.uid)
    .all();
  return results.map((r) => ({ ...r, mine: r.mine === 1 }));
}

/**
 * Stemmen (of je stem intrekken). Hoogstens 3 open stemmen per Supporter: de telling zit in de insert zelf, zodat
 * twee stemmen tegelijk samen niet over de grens kunnen (in Supabase een advisory lock).
 */
async function roadmap_vote(ctx, p) {
  const item = uuid(p.p_item);
  const st = (await ctx.db.prepare('SELECT status FROM roadmap_items WHERE id = ?').bind(item).first())?.status;
  if (st == null) return 'not_found';
  if (st === 'early' || st === 'done') return 'closed';
  if (!(await proActive(ctx.db, ctx.uid, ctx.now))) return 'not_pro';
  if (!(bool(p.p_on) ?? false)) {
    await ctx.db.prepare('DELETE FROM roadmap_votes WHERE item_id = ? AND user_id = ?').bind(item, ctx.uid).run();
    return 'ok';
  }
  const [, mine] = await ctx.db.batch([
    ctx.db
      .prepare(
        `INSERT INTO roadmap_votes (item_id, user_id, created_at) SELECT ?, ?, ?
         WHERE NOT EXISTS (SELECT 1 FROM roadmap_votes WHERE item_id = ? AND user_id = ?)
           AND (SELECT count(*) FROM roadmap_votes v JOIN roadmap_items i ON i.id = v.item_id
                WHERE v.user_id = ? AND i.status NOT IN ('early', 'done')) < 3`,
      )
      .bind(item, ctx.uid, ctx.now.toISOString(), item, ctx.uid, ctx.uid),
    ctx.db.prepare('SELECT 1 FROM roadmap_votes WHERE item_id = ? AND user_id = ?').bind(item, ctx.uid),
  ]);
  return mine.results.length ? 'ok' : 'limit';
}

/** Een nieuw meldingstoken voor dit toestel; alleen de 5 nieuwste per gebruiker blijven. */
async function notify_register(ctx) {
  const token = crypto.randomUUID();
  await ctx.db.batch([
    ctx.db.prepare('INSERT INTO notify_tokens (token, user_id, created_at) VALUES (?, ?, ?)').bind(token, ctx.uid, ctx.now.toISOString()),
    ctx.db
      .prepare(
        `DELETE FROM notify_tokens WHERE user_id = ? AND token NOT IN (
           SELECT token FROM notify_tokens WHERE user_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 5)`,
      )
      .bind(ctx.uid, ctx.uid),
  ]);
  return token;
}

/** Een eigen meldingstoken weggooien (dat van een ander blijft staan). */
async function notify_unregister(ctx, p) {
  await ctx.db.prepare('DELETE FROM notify_tokens WHERE token = ? AND user_id = ?').bind(uuid(p.p_token), ctx.uid).run();
  return null;
}

/**
 * Open uitdagingen voor de eigenaar van een meldingstoken, voor de achtergrondtaak zonder sessie: alleen het id van
 * de battle en de naam van wie uitdaagt, van de laatste week, hoogstens 10.
 */
async function pending_challenges(ctx, p) {
  const { results } = await ctx.db
    .prepare(
      `SELECT b.id, coalesce(f.name, '') AS name
       FROM notify_tokens t
       JOIN battles b ON b.opponent = t.user_id
       LEFT JOIN friend_profiles f ON f.user_id = b.challenger
       WHERE t.token = ? AND b.accepted = 0 AND b.week >= ?
       ORDER BY b.created_at DESC
       LIMIT 10`,
    )
    .bind(uuid(p.p_token), utcDay(ctx.now, -7))
    .all();
  return results;
}
pending_challenges.anon = true;

export default {
  ai_quota,
  ai_quota_use,
  ai_report,
  photo_quota,
  photo_quota_use,
  my_pro,
  pro_show_badge,
  pro_set_frame,
  my_features,
  roadmap_list,
  roadmap_vote,
  notify_register,
  notify_unregister,
  pending_challenges,
};
