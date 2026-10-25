// Vrienden (friend_profiles, friendships), blokkeren en melden (user_blocks, user_reports) en wekelijkse battles
// (battles). Vertaald uit de security-definer-functies in Supabase: dezelfde controles, meldingen en antwoorden.
// "Vandaag" (current_date) is de UTC-datum van het verzoek. Wie iets nieuws te zien krijgt (een verzoek, een
// uitdaging of een antwoord daarop), krijgt meteen een seintje { type: 'social' }.
import { DbError, raise } from '../errors.js';
import { areFriends, textBlocked } from './shared.js';

const DAY_MS = 86_400_000;
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const REASONS = ['spam', 'harassment', 'inappropriate', 'other'];
const SOCIAL = { type: 'social' };

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

/** Zoals de cast naar date: alleen een bestaande dag 'YYYY-MM-DD'. */
function date(v) {
  if (v == null) return null;
  const s = String(v).trim();
  const d = new Date(`${s}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s) || Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s) {
    throw new DbError('22007', `invalid input syntax for type date: "${v}"`);
  }
  return s;
}

/** Zoals de cast naar integer (een getal als tekst mag ook). */
function int(v) {
  if (v == null) return null;
  const n = typeof v === 'string' && /^\s*-?\d+\s*$/.test(v) ? Number(v) : v;
  if (!Number.isInteger(n)) throw new DbError('22P02', `invalid input syntax for type integer: "${v}"`);
  return n;
}

/** left(btrim(s), n): btrim haalt alleen spaties weg; left telt tekens, geen UTF-16-eenheden. */
const trimLeft = (s, n) => [...String(s ?? '').replace(/^ +| +$/g, '')].slice(0, n).join('');

/** De ingelogde gebruiker (callRpc laat zonder sessie al niemand binnen; dit is de check uit plpgsql). */
function me(ctx) {
  if (!ctx.uid) raise('niet ingelogd');
  return ctx.uid;
}

/** Blokkeerde een van beiden de ander? (als SQL-voorwaarde met de twee ids als parameters) */
const BLOCKED_SQL = 'EXISTS (SELECT 1 FROM user_blocks x WHERE (x.blocker = ?1 AND x.blocked = ?2) OR (x.blocker = ?2 AND x.blocked = ?1))';

/**
 * friend_add: een verzoek sturen met de code van de ander, of zijn verzoek aan jou aanvaarden.
 * Een blokkade (in welke richting ook) geeft 'not_found', zoals een onbestaande code: zo verraadt de uitkomst niets.
 * Geeft { result, other } terug; other is de id van de ander (null als die niet gevonden is).
 */
async function addByCode(ctx, code) {
  const uid = me(ctx);
  const c = code == null ? null : String(code).replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  const other = c === null ? null : await ctx.db.prepare('SELECT user_id FROM friend_profiles WHERE code = ?').bind(c).first('user_id');
  if (other === null) return { result: 'not_found', other: null };
  if (other === uid) return { result: 'self', other };
  if (await ctx.db.prepare(`SELECT ${BLOCKED_SQL} AS b`).bind(uid, other).first('b')) return { result: 'not_found', other: null };
  // Een verzoek van de ander aan jou: aanvaarden (ook als het al aanvaard was, zoals in plpgsql)
  const acc = await ctx.db
    .prepare(`UPDATE friendships SET accepted = 1 WHERE requester = ?2 AND addressee = ?1 AND NOT ${BLOCKED_SQL}`)
    .bind(uid, other)
    .run();
  if (acc.meta.changes > 0) {
    ctx.notify(other, SOCIAL);
    return { result: 'accepted', other };
  }
  if (await ctx.db.prepare('SELECT 1 FROM friendships WHERE requester = ? AND addressee = ?').bind(uid, other).first()) {
    return { result: 'already', other };
  }
  // Limiet, blokkade en een verzoek in de andere richting zitten in dezelfde insert, zodat twee gelijktijdige
  // verzoeken de limiet niet samen kunnen overschrijden
  const ins = await ctx.db
    .prepare(
      `INSERT INTO friendships (requester, addressee, accepted, created_at)
       SELECT ?1, ?2, 0, ?3
       WHERE (SELECT count(*) FROM friendships WHERE requester = ?1 AND accepted = 0) < 50
         AND NOT ${BLOCKED_SQL}
         AND NOT EXISTS (SELECT 1 FROM friendships WHERE requester = ?2 AND addressee = ?1)
       ON CONFLICT DO NOTHING`,
    )
    .bind(uid, other, ctx.now.toISOString())
    .run();
  if (ins.meta.changes > 0) {
    ctx.notify(other, SOCIAL);
    return { result: 'requested', other };
  }
  // Niet ingevoegd: de limiet, of iets dat tussen de controles en de insert veranderde (zeldzaam; dan is de
  // uitkomst 'already' en toont de app na het herladen de echte stand)
  const open = await ctx.db.prepare('SELECT count(*) AS n FROM friendships WHERE requester = ? AND accepted = 0').bind(uid).first('n');
  if (open >= 50) raise('te veel openstaande verzoeken');
  return { result: 'already', other };
}

/** friend_list en friend_list_v2: je vrienden en verzoeken, met de score van deze en vorige week (alleen van vrienden). */
async function friendRows(ctx, week, withSupporter) {
  const uid = me(ctx);
  const w = date(week);
  const { results } = await ctx.db
    .prepare(
      `WITH mine AS (
         SELECT CASE WHEN f.requester = ?1 THEN f.addressee ELSE f.requester END AS other,
           CASE WHEN f.accepted THEN 'friend' WHEN f.requester = ?1 THEN 'outgoing' ELSE 'incoming' END AS state
         FROM friendships f
         WHERE f.requester = ?1 OR f.addressee = ?1
       )
       SELECT m.other, coalesce(p.name, '') AS name, m.state,
         w.score, w.days, v.score AS prev_score, v.days AS prev_days, p.avatar, coalesce(p.level, 1) AS level,
         CASE WHEN m.state = 'friend' THEN p.title END AS title, CASE WHEN m.state = 'friend' THEN p.badges END AS badges,
         m.state = 'friend' AND EXISTS (
           SELECT 1 FROM pro_status s WHERE s.user_id = m.other AND s.until > ?4 AND s.show_badge
         ) AS supporter
       FROM mine m
       LEFT JOIN friend_profiles p ON p.user_id = m.other
       LEFT JOIN weekly_scores w ON m.state = 'friend' AND w.user_id = m.other AND w.week = ?2
       LEFT JOIN weekly_scores v ON m.state = 'friend' AND v.user_id = m.other AND v.week = ?3
       ORDER BY m.state, coalesce(p.name, '')`,
    )
    .bind(uid, w, w === null ? null : utcDay(new Date(`${w}T00:00:00Z`), -7), ctx.now.toISOString())
    .all();
  return results.map(({ supporter, ...r }) => (withSupporter ? { ...r, supporter: supporter === 1 } : r));
}


/**
 * Hebben [uid] en [other] een band: vriend of (openstaand) verzoek, een blokkade, een battle, of samen in een
 * uitdaging (ook een uitnodiging)? Alleen dan mag je iemand blokkeren of melden.
 */
async function linkedTo(db, uid, other) {
  return !!(await db
    .prepare(
      `SELECT EXISTS (SELECT 1 FROM friendships f WHERE (f.requester = ?1 AND f.addressee = ?2) OR (f.requester = ?2 AND f.addressee = ?1))
         OR EXISTS (SELECT 1 FROM user_blocks x WHERE x.blocker = ?1 AND x.blocked = ?2)
         OR EXISTS (SELECT 1 FROM battles b WHERE (b.challenger = ?1 AND b.opponent = ?2) OR (b.challenger = ?2 AND b.opponent = ?1))
         OR EXISTS (SELECT 1 FROM challenge_members a JOIN challenge_members o ON o.challenge_id = a.challenge_id
                    WHERE a.user_id = ?1 AND o.user_id = ?2) AS linked`,
    )
    .bind(uid, other)
    .first('linked'));
}

export default {
  /**
   * Je eigen vriendenprofiel: maakt het aan (met een nieuwe code van 8 tekens) als het er nog niet is, en werkt
   * naam, avatar en level bij. p_avatar null = ongewijzigd, '' = wissen; het level gaat nooit omlaag.
   * Werkt met alleen p_name (de oude vorm) en zonder parameters.
   */
  async friend_me(ctx, p) {
    const uid = me(ctx);
    const name = p.p_name == null ? null : trimLeft(text(p.p_name), 40);
    if (name !== null && textBlocked(name)) throw new DbError('22023', 'name_not_allowed', { hint: 'Kies een andere naam.' });
    const avatar = text(p.p_avatar);
    const level = int(p.p_level);
    const now = ctx.now.toISOString();
    // Een nieuwe code die toevallig al bestaat, wordt stil genegeerd (INSERT OR IGNORE): dan opnieuw met een andere
    for (let i = 0; i < 20; i++) {
      let code = '';
      for (let j = 0; j < 8; j++) code += ALPHABET[crypto.getRandomValues(new Uint32Array(1))[0] % ALPHABET.length];
      const [, , row] = await ctx.db.batch([
        ctx.db.prepare('INSERT OR IGNORE INTO friend_profiles (user_id, code, updated_at) VALUES (?, ?, ?)').bind(uid, code, now),
        ctx.db
          .prepare(
            `UPDATE friend_profiles SET
               name = coalesce(?2, name),
               avatar = CASE WHEN ?3 IS NULL THEN avatar ELSE nullif(?3, '') END,
               level = CASE WHEN ?4 IS NULL THEN level ELSE max(level, ?4) END,
               updated_at = ?5
             WHERE user_id = ?1`,
          )
          .bind(uid, name, avatar, level, now),
        ctx.db.prepare('SELECT code, name FROM friend_profiles WHERE user_id = ?').bind(uid),
      ]);
      if (row.results.length) return row.results;
    }
    throw new DbError('XX000', 'geen vrije vriendencode gevonden', { status: 500 });
  },

  /** Een vriend toevoegen met zijn code. Uitkomst: requested, accepted, already, self of not_found. */
  async friend_add(ctx, p) {
    return (await addByCode(ctx, p.p_code)).result;
  },

  /**
   * Zoals friend_add, maar zegt ook wanneer jullie al vrienden zijn ('friends') en met wie (other). Bij een
   * blokkade 'not_found' zonder id, anders zou de id de blokkade verraden.
   */
  async friend_add_v2(ctx, p) {
    const uid = me(ctx);
    const c = p.p_code == null ? null : String(p.p_code).replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    const o = c === null ? null : await ctx.db.prepare('SELECT user_id FROM friend_profiles WHERE code = ?').bind(c).first('user_id');
    if (o === null) return [{ result: 'not_found', other: null }];
    if (o === uid) return [{ result: 'self', other: o }];
    if (await areFriends(ctx.db, uid, uid, o)) return [{ result: 'friends', other: o }];
    const { result } = await addByCode(ctx, p.p_code);
    return [{ result, other: result === 'not_found' ? null : o }];
  },

  /** Vrienden en verzoeken met hun weekscore (p_week = maandag van deze week). */
  async friend_list(ctx, p) {
    return friendRows(ctx, p.p_week, false);
  },

  /** Zoals friend_list, plus of een vriend het Supporter-badge toont. */
  async friend_list_v2(ctx, p) {
    return friendRows(ctx, p.p_week, true);
  },

  /**
   * De supporterranden van wie je ziet: bevestigde vrienden, tegenstanders uit je battles en medespelers in je
   * uitdagingen. Alleen wie Pro heeft, het badge toont en een rand koos; niemand met een blokkade tussen jullie.
   */
  async friend_frames(ctx) {
    const uid = me(ctx);
    const { results } = await ctx.db
      .prepare(
        `WITH people AS (
           SELECT CASE WHEN f.requester = ?1 THEN f.addressee ELSE f.requester END AS other
           FROM friendships f
           WHERE f.accepted AND (f.requester = ?1 OR f.addressee = ?1)
           UNION
           SELECT CASE WHEN b.challenger = ?1 THEN b.opponent ELSE b.challenger END
           FROM battles b
           WHERE b.challenger = ?1 OR b.opponent = ?1
           UNION
           SELECT m2.user_id
           FROM challenge_members m1
           JOIN challenge_members m2 ON m2.challenge_id = m1.challenge_id AND m2.user_id <> m1.user_id
           WHERE m1.user_id = ?1 AND m1.accepted AND m2.accepted
         )
         SELECT p.other, s.frame
         FROM people p
         JOIN pro_status s ON s.user_id = p.other
         WHERE s.until > ?2 AND s.show_badge AND s.frame IS NOT NULL
           AND NOT EXISTS (
             SELECT 1 FROM user_blocks k
             WHERE (k.blocker = ?1 AND k.blocked = p.other) OR (k.blocker = p.other AND k.blocked = ?1)
           )`,
      )
      .bind(uid, ctx.now.toISOString())
      .all();
    return results;
  },

  /** Titel (max. 40 tekens) en badges (max. 2000 tekens) op je eigen vriendenprofiel; leeg = geen. */
  async friend_extra(ctx, p) {
    const uid = me(ctx);
    const title = trimLeft(text(p.p_title), 40) || null;
    const badges = [...(text(p.p_badges) ?? '')].slice(0, 2000).join('') || null;
    await ctx.db
      .prepare('UPDATE friend_profiles SET title = ?, badges = ?, updated_at = ? WHERE user_id = ?')
      .bind(title, badges, ctx.now.toISOString(), uid)
      .run();
    return null;
  },

  /** Een verzoek van p_other aan jou aanvaarden of weigeren. Weigeren wist alleen een nog open verzoek. */
  async friend_respond(ctx, p) {
    const uid = me(ctx);
    const other = uuid(p.p_other);
    if (bool(p.p_accept)) {
      // accepted = 0 erbij: het resultaat is hetzelfde, maar zo krijgt de ander alleen een seintje als er iets veranderde
      const r = await ctx.db.prepare('UPDATE friendships SET accepted = 1 WHERE requester = ? AND addressee = ? AND accepted = 0').bind(other, uid).run();
      if (r.meta.changes > 0) ctx.notify(other, SOCIAL);
    } else {
      await ctx.db.prepare('DELETE FROM friendships WHERE requester = ? AND addressee = ? AND accepted = 0').bind(other, uid).run();
    }
    return null;
  },

  /** Een vriendschap of verzoek (in welke richting ook) tussen jou en p_other wissen. */
  async friend_remove(ctx, p) {
    const uid = me(ctx);
    await ctx.db
      .prepare('DELETE FROM friendships WHERE (requester = ?1 AND addressee = ?2) OR (requester = ?2 AND addressee = ?1)')
      .bind(uid, uuid(p.p_other))
      .run();
    return null;
  },

  /**
   * Iemand blokkeren: de vriendschap of het verzoek verdwijnt, net als openstaande battles en battles van deze of
   * een volgende week (afgelopen battles blijven in je geschiedenis) en niet-aanvaarde uitnodigingen voor
   * uitdagingen tussen jullie. Wie geblokkeerd wordt, krijgt daar geen seintje van. Hoogstens 1000 blokkades.
   */
  async friend_block(ctx, p) {
    const uid = me(ctx);
    const other = uuid(p.p_other);
    if (other === null || other === uid) return null;
    // Alleen iemand die je kent: anders zou een willekeurige id in je blokkeerlijst diens naam en avatar tonen. Een
    // onbekende id antwoordt hetzelfde als een die niet bestaat (niets, en niets bewaard).
    if (!(await linkedTo(ctx.db, uid, other))) return null;
    const n = await ctx.db.prepare('SELECT count(*) AS n FROM user_blocks WHERE blocker = ?').bind(uid).first('n');
    if (n >= 1000) raise('te veel blokkades');
    // De limiet zit ook in de insert en het opruimen alleen als de blokkade er echt staat: zo kunnen gelijktijdige
    // verzoeken de limiet niet overschrijden en wordt er nooit iets gewist zonder blokkade
    const blocked = 'EXISTS (SELECT 1 FROM user_blocks WHERE blocker = ?1 AND blocked = ?2)';
    const [ins] = await ctx.db.batch([
      ctx.db
        .prepare(
          `INSERT INTO user_blocks (blocker, blocked, created_at) SELECT ?1, ?2, ?3
           WHERE (SELECT count(*) FROM user_blocks WHERE blocker = ?1) < 1000
           ON CONFLICT DO NOTHING RETURNING blocker`,
        )
        .bind(uid, other, ctx.now.toISOString()),
      ctx.db
        .prepare(`DELETE FROM friendships WHERE ((requester = ?1 AND addressee = ?2) OR (requester = ?2 AND addressee = ?1)) AND ${blocked}`)
        .bind(uid, other),
      ctx.db
        .prepare(
          `DELETE FROM battles
           WHERE ((challenger = ?1 AND opponent = ?2) OR (challenger = ?2 AND opponent = ?1))
             AND (NOT accepted OR date(week, '+7 days') > ?3) AND ${blocked}`,
        )
        .bind(uid, other, utcDay(ctx.now)),
      ctx.db
        .prepare(
          `DELETE FROM challenge_members
           WHERE NOT accepted AND ((user_id = ?1 AND invited_by = ?2) OR (user_id = ?2 AND invited_by = ?1)) AND ${blocked}`,
        )
        .bind(uid, other),
    ]);
    if (!ins.results.length && !(await ctx.db.prepare('SELECT 1 FROM user_blocks WHERE blocker = ? AND blocked = ?').bind(uid, other).first())) {
      raise('te veel blokkades');
    }
    return null;
  },

  /** Een blokkade opheffen. Vrienden worden jullie pas opnieuw met een nieuw verzoek. */
  async friend_unblock(ctx, p) {
    const uid = me(ctx);
    await ctx.db.prepare('DELETE FROM user_blocks WHERE blocker = ? AND blocked = ?').bind(uid, uuid(p.p_other)).run();
    return null;
  },

  /** Wie jij blokkeerde (niet wie jou blokkeerde), met naam en avatar, nieuwste eerst. */
  async friend_blocked_list(ctx) {
    const uid = me(ctx);
    const { results } = await ctx.db
      .prepare(
        `SELECT x.blocked AS other, coalesce(p.name, '') AS name, p.avatar, x.created_at
         FROM user_blocks x
         LEFT JOIN friend_profiles p ON p.user_id = x.blocked
         WHERE x.blocker = ?
         ORDER BY x.created_at DESC`,
      )
      .bind(uid)
      .all();
    return results;
  },

  /**
   * Iemand melden. Alleen iemand met wie je een band hebt (vriend, verzoek, blokkade, battle of samen in een
   * uitdaging), zodat je geen willekeurige accounts kan melden. Naam en avatar van dat moment gaan mee.
   * Uitkomst: reported, limit (10 per dag, samen met challenge_report), bad_reason of not_found.
   */
  async friend_report(ctx, p) {
    const uid = me(ctx);
    const note = trimLeft(text(p.p_note), 500) || null;
    const reason = text(p.p_reason);
    if (reason === null || !REASONS.includes(reason)) return 'bad_reason';
    const other = uuid(p.p_other);
    if (other === null || other === uid) return 'not_found';
    if (!(await linkedTo(ctx.db, uid, other))) return 'not_found';
    // De daglimiet in dezelfde insert: gelijktijdige meldingen kunnen ze niet samen overschrijden
    const r = await ctx.db
      .prepare(
        `INSERT INTO user_reports (id, reporter, reported, reason, note, reported_name, reported_avatar, created_at)
         SELECT ?1, ?2, ?3, ?4, ?5, p.name, p.avatar, ?6
         FROM (SELECT 1) one
         LEFT JOIN friend_profiles p ON p.user_id = ?3
         WHERE (SELECT count(*) FROM user_reports r WHERE r.reporter = ?2 AND r.created_at > ?7) < 10`,
      )
      .bind(crypto.randomUUID(), uid, other, reason, note, ctx.now.toISOString(), new Date(ctx.now.getTime() - DAY_MS).toISOString())
      .run();
    return r.meta.changes > 0 ? 'reported' : 'limit';
  },

  /**
   * Een vriend uitdagen voor de week die op p_week (maandag) begint: deze week, vorige week (tot 8 dagen terug, voor
   * de maandag voor 03:00) of volgende week. Had die jou al uitgedaagd, dan is de battle meteen aanvaard.
   * Uitkomst: created, accepted, exists, not_friends of bad_week.
   */
  async battle_challenge(ctx, p) {
    const uid = me(ctx);
    const week = date(p.p_week);
    // Een lege week was in plpgsql een null-voorwaarde en daarna een fout bij de insert; hier gewoon bad_week
    if (week === null || new Date(`${week}T00:00:00Z`).getUTCDay() !== 1 || week < utcDay(ctx.now, -8) || week > utcDay(ctx.now, 7)) {
      return 'bad_week';
    }
    const other = uuid(p.p_other);
    if (other === null || !(await areFriends(ctx.db, uid, uid, other))) return 'not_friends';
    // Een open uitdaging van de ander voor die week: aanvaarden
    const acc = await ctx.db
      .prepare('UPDATE battles SET accepted = 1 WHERE week = ? AND challenger = ? AND opponent = ? AND accepted = 0')
      .bind(week, other, uid)
      .run();
    if (acc.meta.changes > 0) {
      ctx.notify(other, SOCIAL);
      return 'accepted';
    }
    // De unieke index battles_pair_week laat per paar en week maar één battle toe: bestaat ze al, dan 'exists'.
    // De vriendschap staat in dezelfde insert, zodat er geen battle komt als ze net verdween.
    const ins = await ctx.db
      .prepare(
        `INSERT INTO battles (id, week, challenger, opponent, accepted, created_at)
         SELECT ?1, ?2, ?3, ?4, 0, ?5
         WHERE EXISTS (SELECT 1 FROM friendships f WHERE f.accepted
                       AND ((f.requester = ?3 AND f.addressee = ?4) OR (f.requester = ?4 AND f.addressee = ?3)))
         ON CONFLICT DO NOTHING`,
      )
      .bind(crypto.randomUUID(), week, uid, other, ctx.now.toISOString())
      .run();
    if (ins.meta.changes > 0) {
      ctx.notify(other, SOCIAL);
      return 'created';
    }
    // Race: daagde de ander jou net tussen de update en de insert uit, dan is dit 'exists' (plpgsql gaf daar
    // een unieke-sleutelfout); de app toont na het herladen de uitdaging om te aanvaarden
    return 'exists';
  },

  /** Een uitdaging aannemen of weigeren (alleen door wie uitgedaagd werd). Weigeren wist alleen een open uitdaging. */
  async battle_respond(ctx, p) {
    const uid = me(ctx);
    const id = uuid(p.p_id);
    const stmt = bool(p.p_accept)
      ? 'UPDATE battles SET accepted = 1 WHERE id = ? AND opponent = ? RETURNING challenger'
      : 'DELETE FROM battles WHERE id = ? AND opponent = ? AND accepted = 0 RETURNING challenger';
    const { results } = await ctx.db.prepare(stmt).bind(id, uid).all();
    for (const r of results) ctx.notify(r.challenger, SOCIAL);
    return null;
  },

  /** Je eigen uitdaging intrekken zolang ze niet aanvaard is. */
  async battle_cancel(ctx, p) {
    const uid = me(ctx);
    const { results } = await ctx.db
      .prepare('DELETE FROM battles WHERE id = ? AND challenger = ? AND accepted = 0 RETURNING opponent')
      .bind(uuid(p.p_id), uid)
      .all();
    for (const r of results) ctx.notify(r.opponent, SOCIAL);
    return null;
  },

  /**
   * Je battles: alle aanvaarde, en open uitdagingen van de laatste twee weken, met de punten van jou en de ander.
   * Nieuwste week eerst.
   */
  async battle_list(ctx) {
    const uid = me(ctx);
    const { results } = await ctx.db
      .prepare(
        `SELECT b.id, b.week, b.challenger = ?1 AS challenged_by_me, b.accepted,
           b.other, coalesce(p.name, '') AS other_name, p.avatar AS other_avatar, coalesce(p.level, 1) AS other_level,
           p.title AS other_title, coalesce(mw.points, 0) AS my_points, coalesce(mw.mid_points, 0) AS my_mid,
           coalesce(ow.points, 0) AS other_points, coalesce(ow.mid_points, 0) AS other_mid
         FROM (
           SELECT x.*, CASE WHEN x.challenger = ?1 THEN x.opponent ELSE x.challenger END AS other
           FROM battles x
           WHERE (x.challenger = ?1 OR x.opponent = ?1) AND (x.accepted OR x.week >= ?2)
         ) b
         LEFT JOIN friend_profiles p ON p.user_id = b.other
         LEFT JOIN weekly_scores mw ON mw.user_id = ?1 AND mw.week = b.week
         LEFT JOIN weekly_scores ow ON ow.user_id = b.other AND ow.week = b.week
         ORDER BY b.week DESC, b.created_at DESC`,
      )
      .bind(uid, utcDay(ctx.now, -14))
      .all();
    return results.map((r) => ({ ...r, challenged_by_me: r.challenged_by_me === 1, accepted: r.accepted === 1 }));
  },
};
