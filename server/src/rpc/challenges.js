// Uitdagingen met vrienden: challenge_create, _invite, _respond, _leave, _list, _report, en challenge_days_put (was
// in Supabase een upsert op challenge_days met RLS). Vertaald uit de security-definer-functies daar: dezelfde
// controles, meldingen en antwoorden. challenges en challenge_members zijn alleen via deze functies bereikbaar.
// current_date is de UTC-datum van ctx.now (Supabase draaide in UTC); datums zijn 'YYYY-MM-DD', dus vergelijken
// als tekst klopt.
import { DbError, raise } from '../errors.js';
import { areFriends, textBlocked } from './shared.js';

const DAY_MS = 86_400_000;
const MAX_MEMBERS = 20; // per uitdaging
const MAX_RUNNING = 20; // lopende uitdagingen per gebruiker
const MAX_REPORTS = 10; // meldingen per 24 uur (samen met friend_report)
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** UTC-datum 'YYYY-MM-DD' van [now], eventueel [days] dagen verschoven. */
const utcDay = (now, days = 0) => new Date(now.getTime() + days * DAY_MS).toISOString().slice(0, 10);

/** Een tekstparameter zoals PostgREST hem doorgeeft (null blijft null). */
const text = (v) => (v == null ? null : typeof v === 'object' ? JSON.stringify(v) : String(v));

/** btrim (alleen spaties) en left(…, n) zoals in Postgres: op tekens, niet op UTF-16-eenheden. */
const trimLeft = (v, n) => [...String(v ?? '').replace(/^ +| +$/g, '')].slice(0, n).join('');

/** Een uuid-parameter: null mag, iets anders dan een uuid niet (22P02 zoals de cast in Postgres). */
function uuid(v) {
  if (v == null) return null;
  if (typeof v !== 'string' || !UUID.test(v)) throw new DbError('22P02', `invalid input syntax for type uuid: "${v}"`);
  return v.toLowerCase();
}

/** Een datum 'YYYY-MM-DD' (22007 zoals Postgres bij iets anders); null blijft null. */
function date(v) {
  if (v == null) return null;
  const s = String(v);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s) || Number.isNaN(Date.parse(`${s}T00:00:00Z`)) || new Date(`${s}T00:00:00Z`).toISOString().slice(0, 10) !== s)
    throw new DbError('22007', `invalid input syntax for type date: "${s}"`);
  return s;
}

/** Een geheel getal (ook als tekst, zoals PostgREST het doorgeeft); null blijft null. */
function int(v) {
  if (v == null) return null;
  const n = typeof v === 'string' && /^\s*-?\d+\s*$/.test(v) ? Number(v) : v;
  if (!Number.isInteger(n)) throw new DbError('22P02', `invalid input syntax for type integer: "${v}"`);
  return n;
}

/** Een getal (double precision); null blijft null. */
function num(v) {
  if (v == null) return null;
  const n = typeof v === 'string' && v.trim() !== '' ? Number(v) : v;
  if (typeof n !== 'number' || !Number.isFinite(n)) throw new DbError('22P02', `invalid input syntax for type double precision: "${v}"`);
  return n;
}

/** Zoals de cast naar boolean in Postgres; null blijft null. */
function bool(v) {
  if (v == null || typeof v === 'boolean') return v ?? null;
  const s = String(v).trim().toLowerCase();
  if (['t', 'true', 'y', 'yes', 'on', '1'].includes(s)) return true;
  if (['f', 'false', 'n', 'no', 'off', '0'].includes(s)) return false;
  throw new DbError('22P02', `invalid input syntax for type boolean: "${v}"`);
}

/** Zoals challenge_member: ben jij ([user] = jezelf) aanvaard deelnemer? */
async function challengeMember(ctx, challenge, user) {
  if (ctx.uid !== user) return false;
  const r = await ctx.db
    .prepare('SELECT 1 FROM challenge_members WHERE challenge_id = ? AND user_id = ? AND accepted = 1 LIMIT 1')
    .bind(challenge, user)
    .first();
  return r !== null;
}

/** Zoals challenge_day_ok, met de uitdaging al opgehaald: binnen de looptijd en hoogstens morgen. */
const dayOk = (c, day, now) => c != null && day >= c.start_day && day < utcDay(new Date(`${c.start_day}T00:00:00Z`), c.days) && day <= utcDay(now, 1);

const rlsError = () =>
  new DbError('42501', 'new row violates row-level security policy for table "challenge_days"', { status: 403 });

export default {
  /** Een uitdaging starten en meteen vrienden uitnodigen (alleen bevestigde vrienden; de rest wordt overgeslagen). */
  async challenge_create(ctx, p) {
    const me = ctx.uid;
    const title = trimLeft(text(p.p_title), 60);
    if (textBlocked(title)) throw new DbError('22023', 'title_not_allowed', { hint: 'Kies een andere titel.' });
    const start = date(p.p_start);
    const today = utcDay(ctx.now);
    if (start !== null && (start < utcDay(ctx.now, -1) || start > utcDay(ctx.now, 14))) raise('startdag buiten bereik');
    const days = int(p.p_days), need = int(p.p_need), amount = num(p.p_amount) ?? 0;
    if (p.p_invite != null && !Array.isArray(p.p_invite)) throw new DbError('22P02', `malformed array literal: "${text(p.p_invite)}"`);
    const invite = (p.p_invite ?? []).map((x) => {
      if (x != null && typeof x !== 'string') throw new DbError('22P02', `invalid input syntax for type uuid: "${text(x)}"`);
      return x;
    });

    // are_friends voor de hele lijst in één keer: wie met jou bevriend is
    const friends = new Set(
      (
        await ctx.db
          .prepare('SELECT CASE WHEN requester = ? THEN addressee ELSE requester END AS f FROM friendships WHERE accepted = 1 AND (requester = ? OR addressee = ?)')
          .bind(me, me, me)
          .all()
      ).results.map((r) => r.f),
    );
    // Zoals de lus in plpgsql: stoppen bij 20 deelnemers (jij telt mee), dubbels en niet-vrienden overslaan
    const invited = [];
    for (const other of invite) {
      if (invited.length + 1 >= MAX_MEMBERS) break;
      if (other != null && other !== me && friends.has(other) && !invited.includes(other)) invited.push(other);
    }

    const id = crypto.randomUUID();
    const at = ctx.now.toISOString();
    // De limiet van 20 lopende uitdagingen zit in de insert zelf: twee gelijktijdige aanroepen kunnen er zo niet
    // samen overheen. Wordt de uitdaging niet aangemaakt, dan voegen de volgende statements niets toe.
    const member = (uid, by, accepted) =>
      ctx.db
        .prepare('INSERT INTO challenge_members (challenge_id, user_id, invited_by, accepted, created_at) SELECT ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM challenges WHERE id = ?)')
        .bind(id, uid, by, accepted, at, id);
    const out = await ctx.db.batch([
      ctx.db
        .prepare(
          `INSERT INTO challenges (id, owner, template, title, nutrient, rule, amount, days, need, start_day, created_at)
           SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
           WHERE (SELECT count(*) FROM challenge_members m JOIN challenges c ON c.id = m.challenge_id
                  WHERE m.user_id = ? AND date(c.start_day, '+' || c.days || ' days') >= ?) < ?
           RETURNING id`,
        )
        .bind(id, me, text(p.p_template), title === '' ? null : title, text(p.p_nutrient), text(p.p_rule), amount, days, need, start, at, me, today, MAX_RUNNING),
      member(me, me, 1),
      ...invited.map((other) => member(other, me, 0)),
    ]);
    if (out[0].results.length === 0) raise('te veel lopende uitdagingen');
    for (const other of invited) ctx.notify(other, { type: 'social' });
    return id;
  },

  /** Een vriend uitnodigen voor een uitdaging waar je zelf aan meedoet. Geeft invited, exists, not_friends, full,
   *  finished of not_member. */
  async challenge_invite(ctx, p) {
    const me = ctx.uid;
    const id = uuid(p.p_id);
    const other = text(p.p_other);
    if (!(await challengeMember(ctx, id, me))) return 'not_member';
    const today = utcDay(ctx.now);
    const done = await ctx.db.prepare("SELECT 1 FROM challenges WHERE id = ? AND date(start_day, '+' || days || ' days') <= ?").bind(id, today).first();
    if (done) return 'finished';
    if (!(await areFriends(ctx.db, me, me, other))) return 'not_friends';
    // Bestaat al en vol: in de insert zelf, zodat gelijktijdige uitnodigingen niet boven de 20 uitkomen
    const r = await ctx.db
      .prepare(
        `INSERT INTO challenge_members (challenge_id, user_id, invited_by, created_at)
         SELECT ?, ?, ?, ? WHERE (SELECT count(*) FROM challenge_members WHERE challenge_id = ?) < ?
         ON CONFLICT (challenge_id, user_id) DO NOTHING RETURNING user_id`,
      )
      .bind(id, other, me, ctx.now.toISOString(), id, MAX_MEMBERS)
      .all();
    if (r.results.length === 0) {
      const exists = await ctx.db.prepare('SELECT 1 FROM challenge_members WHERE challenge_id = ? AND user_id = ?').bind(id, other).first();
      return exists ? 'exists' : 'full';
    }
    ctx.notify(other, { type: 'social' });
    return 'invited';
  },

  /** Een uitnodiging aannemen of weigeren (null telt als weigeren, zoals `if p_accept` in plpgsql). */
  async challenge_respond(ctx, p) {
    const id = uuid(p.p_id);
    const accept = bool(p.p_accept) === true;
    // accepted = 0 bij aannemen verandert niets aan de uitkomst; zo krijgt alleen een echte wijziging een seintje
    const r = await ctx.db
      .prepare(
        accept
          ? 'UPDATE challenge_members SET accepted = 1 WHERE challenge_id = ? AND user_id = ? AND accepted = 0 RETURNING invited_by'
          : 'DELETE FROM challenge_members WHERE challenge_id = ? AND user_id = ? AND accepted = 0 RETURNING invited_by',
      )
      .bind(id, ctx.uid)
      .all();
    const by = r.results[0]?.invited_by;
    if (by && by !== ctx.uid) ctx.notify(by, { type: 'social' });
    return null;
  },

  /** Stoppen met een uitdaging: je dagen en je plaats verdwijnen. Is er niemand meer over, dan verdwijnt ze helemaal. */
  async challenge_leave(ctx, p) {
    const id = uuid(p.p_id);
    await ctx.db.batch([
      ctx.db.prepare('DELETE FROM challenge_days WHERE challenge_id = ? AND user_id = ?').bind(id, ctx.uid),
      ctx.db.prepare('DELETE FROM challenge_members WHERE challenge_id = ? AND user_id = ?').bind(id, ctx.uid),
      ctx.db
        .prepare('DELETE FROM challenges WHERE id = ? AND NOT EXISTS (SELECT 1 FROM challenge_members m WHERE m.challenge_id = ? AND m.accepted = 1)')
        .bind(id, id),
    ]);
    return null;
  },

  /** Je uitdagingen (meegedaan of uitgenodigd, tot 60 dagen na het einde), één rij per deelnemer, met het aantal
   *  gehaalde dagen. Wie jij blokkeerde of wie jou blokkeerde, staat er niet bij. */
  async challenge_list(ctx) {
    const me = ctx.uid;
    const { results } = await ctx.db
      .prepare(
        `SELECT c.id, c.template, c.title, c.nutrient, c.rule, c.amount, c.days, c.need, c.start_day,
           c.owner = ?1 AS owner_is_me, coalesce(ip.name, '') AS invited_by_name,
           m.user_id AS member, coalesce(p.name, '') AS member_name, p.avatar AS member_avatar,
           coalesce(p.level, 1) AS member_level, m.accepted AS member_accepted,
           (SELECT count(*) FROM challenge_days d WHERE d.challenge_id = c.id AND d.user_id = m.user_id AND d.met = 1) AS member_met,
           m.user_id = ?1 AS is_me
         FROM challenge_members mine
         JOIN challenges c ON c.id = mine.challenge_id
         JOIN challenge_members m ON m.challenge_id = c.id
         LEFT JOIN friend_profiles p ON p.user_id = m.user_id
         LEFT JOIN friend_profiles ip ON ip.user_id = mine.invited_by
         WHERE mine.user_id = ?1 AND date(c.start_day, '+' || (c.days + 60) || ' days') >= ?2
           AND NOT EXISTS (
             SELECT 1 FROM user_blocks x
             WHERE (x.blocker = ?1 AND x.blocked = m.user_id) OR (x.blocker = m.user_id AND x.blocked = ?1)
           )
         ORDER BY c.start_day DESC, c.created_at DESC, m.created_at, m.rowid`,
      )
      .bind(me, utcDay(ctx.now))
      .all();
    return results.map((r) => ({ ...r, owner_is_me: r.owner_is_me === 1, member_accepted: r.member_accepted === 1, is_me: r.is_me === 1 }));
  },

  /** Een uitdaging melden om haar titel (tegen wie ze aanmaakte). Geeft reported, limit of not_found. */
  async challenge_report(ctx, p) {
    const me = ctx.uid;
    const id = uuid(p.p_id);
    const note = trimLeft(text(p.p_note), 500) || null;
    const ch = await ctx.db
      .prepare('SELECT c.* FROM challenges c WHERE c.id = ? AND EXISTS (SELECT 1 FROM challenge_members m WHERE m.challenge_id = c.id AND m.user_id = ?)')
      .bind(id, me)
      .first();
    if (!ch || ch.owner === me) return 'not_found';
    // De daglimiet zit in de insert zelf: gelijktijdige meldingen komen er niet samen overheen
    const since = new Date(ctx.now.getTime() - DAY_MS).toISOString();
    const r = await ctx.db
      .prepare(
        `INSERT INTO user_reports (id, reporter, reported, reason, note, reported_name, reported_avatar, challenge_id, challenge_title, created_at)
         SELECT ?, ?, ?, 'challenge_title', ?, p.name, p.avatar, ?, ?, ?
         FROM (SELECT 1) one LEFT JOIN friend_profiles p ON p.user_id = ?
         WHERE (SELECT count(*) FROM user_reports r WHERE r.reporter = ? AND r.created_at > ?) < ?
         RETURNING id`,
      )
      .bind(crypto.randomUUID(), me, ch.owner, note, ch.id, ch.title ?? ch.template, ctx.now.toISOString(), ch.owner, me, since, MAX_REPORTS)
      .all();
    return r.results.length ? 'reported' : 'limit';
  },

  /** Was in Supabase een upsert op challenge_days (RLS: eigen rij, aanvaard deelnemer, dag binnen de looptijd en
   *  hoogstens morgen). [p_days]: { 'YYYY-MM-DD': true/false }. Eén dag die niet mag, en er wordt niets bewaard. */
  async challenge_days_put(ctx, p) {
    const id = uuid(p.p_challenge);
    const input = p.p_days ?? {};
    if (typeof input !== 'object' || Array.isArray(input)) throw new DbError('22P02', 'p_days moet een object zijn');
    const rows = Object.entries(input).map(([day, met]) => {
      const d = date(day);
      const m = bool(met);
      if (m === null) throw new DbError('23502', 'null value in column "met" of relation "challenge_days" violates not-null constraint');
      return [d, m];
    });
    if (rows.length === 0) return null;
    if (!(await challengeMember(ctx, id, ctx.uid))) throw rlsError();
    const c = await ctx.db.prepare('SELECT start_day, days FROM challenges WHERE id = ?').bind(id).first();
    if (!rows.every(([d]) => dayOk(c, d, ctx.now))) throw rlsError();
    // Elke rij opnieuw voorwaardelijk op het lidmaatschap: wie intussen vertrok (challenge_leave), laat geen dagen achter
    const at = ctx.now.toISOString();
    await ctx.db.batch(
      rows.map(([d, m]) =>
        ctx.db
          .prepare(
            `INSERT INTO challenge_days (challenge_id, user_id, day, met, updated_at)
             SELECT ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM challenge_members WHERE challenge_id = ? AND user_id = ? AND accepted = 1)
             ON CONFLICT (challenge_id, user_id, day) DO UPDATE SET met = excluded.met, updated_at = excluded.updated_at`,
          )
          .bind(id, ctx.uid, d, m ? 1 : 0, at, id, ctx.uid),
      ),
    );
    return null;
  },
};
