// RPC's voor vrienden, blokkeren, melden en battles (src/rpc/social.js), via callRpc zoals de app ze aanroept.
// Overgenomen uit supabase/tests (rls_test.mjs, moderation_test.mjs) en aangevuld: elke controle uit de
// security-definer-functies, de vorm van de antwoorden en dat niemand via deze functies bij andermans gegevens kan.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import './workers-stub.mjs';
import { addUser, d1 } from './d1.mjs';

const { callRpc } = await import('../src/rpc/index.js');

const A = 'aaaaaaaa-0000-4000-8000-000000000001';
const B = 'bbbbbbbb-0000-4000-8000-000000000002';
const C = 'cccccccc-0000-4000-8000-000000000003';
const D = 'dddddddd-0000-4000-8000-000000000004';
// Woensdag; de maandag van deze week is 2026-10-26
const NOW = new Date('2026-10-28T12:00:00.000Z');
const WEEK = '2026-10-26';
const PREV = '2026-10-19';
const NEXT = '2026-11-02';

function setup() {
  const db = d1();
  for (const u of [A, B, C, D]) addUser(db, u);
  const sent = [];
  // Nagebootste UserHub: onthoudt wie een seintje kreeg
  const env = { HUB: { idFromName: (u) => u, get: (u) => ({ notify: async (m) => sent.push([u, m]) }) } };
  const call = (uid, name, params = {}, now = NOW) => callRpc(name, params, { db, env, uid, now });
  const sql = (q, ...p) => db.raw.prepare(q).all(...p).map((r) => ({ ...r }));
  const befriend = (a, b, accepted = 1) => sql('INSERT INTO friendships (requester, addressee, accepted) VALUES (?, ?, ?)', a, b, accepted);
  return { db, call, sql, sent, befriend };
}

/** Faalt de belofte met deze code (en melding)? */
const fails = (p, code, message) =>
  assert.rejects(p, (e) => {
    assert.equal(e.code, code);
    if (message !== undefined) assert.equal(e.message, message);
    return true;
  });

/** Een profiel met naam voor elke gebruiker; geeft de codes terug. */
async function profiles(call) {
  const codes = {};
  for (const [u, n] of [[A, 'Anna'], [B, 'Bob'], [C, 'Cleo'], [D, 'Dirk']]) codes[u] = (await call(u, 'friend_me', { p_name: n }))[0].code;
  return codes;
}

// ── Toegang ──

test('zonder sessie kan geen enkele functie, en een onbekende functie geeft PGRST202', async () => {
  const { call } = setup();
  for (const f of ['friend_me', 'friend_add', 'friend_add_v2', 'friend_list', 'friend_list_v2', 'friend_frames', 'friend_extra', 'friend_respond',
    'friend_remove', 'friend_block', 'friend_unblock', 'friend_blocked_list', 'friend_report', 'battle_challenge', 'battle_respond', 'battle_cancel', 'battle_list']) {
    await fails(call(null, f, {}), 'PGRST301');
  }
  await fails(call(A, 'friend_bestaat_niet'), 'PGRST202');
});

test('een ongeldige uuid, datum of boolean geeft dezelfde fout als de cast in Postgres', async () => {
  const { call } = setup();
  await fails(call(A, 'friend_remove', { p_other: 'geen-uuid' }), '22P02');
  await fails(call(A, 'friend_list', { p_week: '2026-02-30' }), '22007');
  await fails(call(A, 'friend_respond', { p_other: B, p_accept: 'misschien' }), '22P02');
  await fails(call(A, 'friend_me', { p_level: 'hoog' }), '22P02');
});

// ── friend_me ──

test('friend_me: maakt een profiel met een code van 8 tekens en houdt die code daarna', async () => {
  const { call } = setup();
  const [me] = await call(A, 'friend_me', { p_name: '  Anna  ', p_avatar: 'av1', p_level: 3 });
  assert.deepEqual(Object.keys(me).sort(), ['code', 'name']);
  assert.match(me.code, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/);
  assert.equal(me.name, 'Anna');
  assert.deepEqual(await call(A, 'friend_me', {}), [{ code: me.code, name: 'Anna' }]);
  assert.notEqual((await call(B, 'friend_me', {}))[0].code, me.code);
  assert.equal((await call(B, 'friend_me', {}))[0].name, '');
});

test('friend_me: scheldnaam geweigerd met name_not_allowed (22023), ook bij een bestaand profiel; oude naam blijft', async () => {
  const { call } = setup();
  await assert.rejects(call(A, 'friend_me', { p_name: 'Fuck you nazi' }), (e) => e.code === '22023' && e.message === 'name_not_allowed' && e.hint === 'Kies een andere naam.');
  assert.equal((await call(A, 'friend_me', { p_name: 'Anna' }))[0].name, 'Anna');
  assert.equal((await call(A, 'friend_me', { p_name: null, p_avatar: null, p_level: 3 }))[0].name, 'Anna', 'zonder naam blijft de naam staan');
  await fails(call(A, 'friend_me', { p_name: 'Shit' }), '22023', 'name_not_allowed');
  assert.equal((await call(A, 'friend_me', {}))[0].name, 'Anna', 'de oude naam blijft na een weigering');
});

test('friend_me: naam max. 40 tekens, avatar null = ongewijzigd en leeg = wissen, level gaat nooit omlaag', async () => {
  const { call, sql } = setup();
  await call(A, 'friend_me', { p_name: `${'é'.repeat(45)}`, p_avatar: 'av', p_level: 5 });
  let [p] = sql('SELECT name, avatar, level FROM friend_profiles WHERE user_id = ?', A);
  assert.equal([...p.name].length, 40);
  assert.equal(p.avatar, 'av');
  await call(A, 'friend_me', { p_name: null, p_avatar: null, p_level: 2 });
  [p] = sql('SELECT avatar, level FROM friend_profiles WHERE user_id = ?', A);
  assert.equal(p.avatar, 'av');
  assert.equal(p.level, 5);
  await call(A, 'friend_me', { p_avatar: '', p_level: 9 });
  [p] = sql('SELECT avatar, level FROM friend_profiles WHERE user_id = ?', A);
  assert.equal(p.avatar, null);
  assert.equal(p.level, 9);
  // Alleen je eigen profiel verandert
  await call(B, 'friend_me', { p_name: 'Bob', p_level: 50 });
  assert.equal(sql('SELECT level FROM friend_profiles WHERE user_id = ?', A)[0].level, 9);
});

// ── friend_add en friend_add_v2 ──

test('friend_add: not_found, self, requested (met seintje), already en accepted', async () => {
  const { call, sql, sent } = setup();
  const codes = await profiles(call);
  assert.equal(await call(A, 'friend_add', { p_code: 'ZZZZZZZZ' }), 'not_found');
  assert.equal(await call(A, 'friend_add', { p_code: null }), 'not_found');
  assert.equal(await call(A, 'friend_add', { p_code: codes[A] }), 'self');
  // Kleine letters, spaties en streepjes tellen niet
  const messy = `${codes[B].slice(0, 4).toLowerCase()} - ${codes[B].slice(4)}`;
  assert.equal(await call(A, 'friend_add', { p_code: messy }), 'requested');
  assert.deepEqual(sent, [[B, { type: 'social' }]]);
  assert.equal(await call(A, 'friend_add', { p_code: codes[B] }), 'already');
  assert.equal(await call(B, 'friend_add', { p_code: codes[A] }), 'accepted');
  assert.deepEqual(sent.at(-1), [A, { type: 'social' }]);
  assert.deepEqual(sql('SELECT requester, addressee, accepted FROM friendships'), [{ requester: A, addressee: B, accepted: 1 }]);
});

test('friend_add: een blokkade in welke richting ook geeft not_found', async () => {
  const { call, sql } = setup();
  const codes = await profiles(call);
  await call(A, 'friend_block', { p_other: B });
  assert.equal(await call(B, 'friend_add', { p_code: codes[A] }), 'not_found');
  assert.equal(await call(A, 'friend_add', { p_code: codes[B] }), 'not_found');
  assert.deepEqual(await call(B, 'friend_add_v2', { p_code: codes[A] }), [{ result: 'not_found', other: null }]);
  assert.equal(sql('SELECT count(*) AS n FROM friendships')[0].n, 0);
});

test('friend_add: hoogstens 50 openstaande verzoeken', async () => {
  const { db, call, sql } = setup();
  await profiles(call);
  for (let i = 0; i < 50; i++) {
    const u = `eeeeeeee-0000-4000-8000-${String(i).padStart(12, '0')}`;
    addUser(db, u);
    sql('INSERT INTO friendships (requester, addressee) VALUES (?, ?)', A, u);
  }
  const code = sql('SELECT code FROM friend_profiles WHERE user_id = ?', B)[0].code;
  await fails(call(A, 'friend_add', { p_code: code }), 'P0001', 'te veel openstaande verzoeken');
  await fails(call(A, 'friend_add_v2', { p_code: code }), 'P0001', 'te veel openstaande verzoeken');
  // Een verzoek van de ander aanvaarden telt niet mee
  sql('INSERT INTO friendships (requester, addressee) VALUES (?, ?)', C, A);
  assert.equal(await call(A, 'friend_add', { p_code: sql('SELECT code FROM friend_profiles WHERE user_id = ?', C)[0].code }), 'accepted');
});

test('friend_add_v2: zegt met wie, en friends als jullie al vrienden zijn', async () => {
  const { call } = setup();
  const codes = await profiles(call);
  assert.deepEqual(await call(A, 'friend_add_v2', { p_code: 'nope' }), [{ result: 'not_found', other: null }]);
  assert.deepEqual(await call(A, 'friend_add_v2', { p_code: codes[A] }), [{ result: 'self', other: A }]);
  assert.deepEqual(await call(A, 'friend_add_v2', { p_code: codes[B] }), [{ result: 'requested', other: B }]);
  assert.deepEqual(await call(A, 'friend_add_v2', { p_code: codes[B] }), [{ result: 'already', other: B }]);
  assert.deepEqual(await call(B, 'friend_add_v2', { p_code: codes[A] }), [{ result: 'accepted', other: A }]);
  assert.deepEqual(await call(B, 'friend_add_v2', { p_code: codes[A] }), [{ result: 'friends', other: A }]);
  assert.deepEqual(await call(A, 'friend_add_v2', { p_code: codes[B] }), [{ result: 'friends', other: B }]);
});

// ── friend_list en friend_list_v2 ──

test('friend_list_v2: staat, volgorde, scores alleen van vrienden, titel en badges alleen voor vrienden', async () => {
  const { call, sql, befriend } = setup();
  await profiles(call);
  sql("UPDATE friend_profiles SET title = 'champion', badges = 'b1', level = 7, avatar = 'avB' WHERE user_id IN (?, ?)", B, C);
  befriend(A, B);
  befriend(A, C, 0);
  befriend(D, A, 0);
  for (const u of [B, C, D]) {
    sql('INSERT INTO weekly_scores (user_id, week, score, days) VALUES (?, ?, 80, 3)', u, WEEK);
    sql('INSERT INTO weekly_scores (user_id, week, score, days) VALUES (?, ?, 60, 7)', u, PREV);
  }
  sql("INSERT INTO pro_status (user_id, until, show_badge) VALUES (?, '2027-01-01T00:00:00.000Z', 1)", B);
  sql("INSERT INTO pro_status (user_id, until, show_badge) VALUES (?, '2027-01-01T00:00:00.000Z', 1)", C);
  const rows = await call(A, 'friend_list_v2', { p_week: WEEK });
  assert.deepEqual(rows, [
    { other: B, name: 'Bob', state: 'friend', score: 80, days: 3, prev_score: 60, prev_days: 7, avatar: 'avB', level: 7, title: 'champion', badges: 'b1', supporter: true },
    { other: D, name: 'Dirk', state: 'incoming', score: null, days: null, prev_score: null, prev_days: null, avatar: null, level: 1, title: null, badges: null, supporter: false },
    { other: C, name: 'Cleo', state: 'outgoing', score: null, days: null, prev_score: null, prev_days: null, avatar: 'avB', level: 7, title: null, badges: null, supporter: false },
  ]);
  // friend_list: dezelfde rijen zonder supporter
  assert.deepEqual(await call(A, 'friend_list', { p_week: WEEK }), rows.map(({ supporter, ...r }) => r));
  // Volgorde binnen een staat op naam
  befriend(C, B);
  sql("UPDATE friend_profiles SET name = 'Aaron' WHERE user_id = ?", C);
  assert.deepEqual((await call(B, 'friend_list', { p_week: WEEK })).map((r) => r.other), [C, A]);
});

test('friend_list_v2: supporter alleen met een lopend abonnement en het badge aan', async () => {
  const { call, sql, befriend } = setup();
  await profiles(call);
  befriend(A, B);
  befriend(A, C);
  sql("INSERT INTO pro_status (user_id, until, show_badge) VALUES (?, '2026-10-01T00:00:00.000Z', 1)", B);
  sql("INSERT INTO pro_status (user_id, until, show_badge) VALUES (?, '2027-01-01T00:00:00.000Z', 0)", C);
  assert.ok((await call(A, 'friend_list_v2', { p_week: WEEK })).every((r) => r.supporter === false));
});

test('friend_list: wie geen vriend is, ziet niets van een ander zijn vrienden of scores', async () => {
  const { call, sql, befriend } = setup();
  await profiles(call);
  befriend(A, B);
  sql('INSERT INTO weekly_scores (user_id, week, score, days) VALUES (?, ?, 80, 3)', B, WEEK);
  assert.deepEqual(await call(C, 'friend_list_v2', { p_week: WEEK }), []);
  assert.deepEqual(await call(C, 'friend_list', { p_week: WEEK }), []);
});

// ── friend_frames ──

test('friend_frames: randen van vrienden, tegenstanders en medespelers met Pro; niet van wie geblokkeerd of zonder badge', async () => {
  const { db, call, sql, befriend } = setup();
  const E = addUser(db, 'eeeeeeee-0000-4000-8000-000000000005');
  const F = addUser(db, 'ffffffff-0000-4000-8000-000000000006');
  // A en B vrienden, A en C in een battle, A en D samen in een uitdaging, E vriend zonder badge, F onbekende met rand
  befriend(A, B);
  befriend(A, E);
  sql("INSERT INTO battles (id, week, challenger, opponent) VALUES ('b1', ?, ?, ?)", PREV, C, A);
  sql("INSERT INTO challenges (id, owner, template, nutrient, rule, days, need, start_day) VALUES ('c1', ?, 'custom', 'fiber', 'min', 7, 7, ?)", D, WEEK);
  sql("INSERT INTO challenge_members (challenge_id, user_id, accepted) VALUES ('c1', ?, 1), ('c1', ?, 1)", A, D);
  for (const [u, frame, badge] of [[B, 'glow', 1], [C, 'orbit', 1], [D, 'crown', 1], [E, 'wings', 0], [F, 'royal', 1]]) {
    sql("INSERT INTO pro_status (user_id, until, show_badge, frame) VALUES (?, '2027-01-01T00:00:00.000Z', ?, ?)", u, badge, frame);
  }
  const frames = async () => Object.fromEntries((await call(A, 'friend_frames')).map((r) => [r.other, r.frame]));
  assert.deepEqual(await frames(), { [B]: 'glow', [C]: 'orbit', [D]: 'crown' });
  assert.deepEqual(Object.keys((await call(A, 'friend_frames'))[0]).sort(), ['frame', 'other']);
  // Een blokkade (ook door de ander) en een afgelopen abonnement halen de rand weg
  sql('INSERT INTO user_blocks (blocker, blocked) VALUES (?, ?)', D, A);
  sql("UPDATE pro_status SET until = '2026-10-01T00:00:00.000Z' WHERE user_id = ?", C);
  assert.deepEqual(await frames(), { [B]: 'glow' });
  // Een uitnodiging die nog niet aanvaard is, telt niet
  sql('DELETE FROM user_blocks');
  sql("UPDATE challenge_members SET accepted = 0 WHERE user_id = ?", D);
  assert.deepEqual(await frames(), { [B]: 'glow' });
  // Wie nergens bij hoort, ziet geen randen
  assert.deepEqual(await call(F, 'friend_frames'), []);
});

// ── friend_extra ──

test('friend_extra: titel en badges op je eigen profiel, leeg wordt null, niets bij een ander', async () => {
  const { call, sql } = setup();
  await profiles(call);
  assert.equal(await call(A, 'friend_extra', { p_title: `  ${'x'.repeat(50)} `, p_badges: 'a,b' }), null);
  let [p] = sql('SELECT title, badges FROM friend_profiles WHERE user_id = ?', A);
  assert.equal(p.title, 'x'.repeat(40));
  assert.equal(p.badges, 'a,b');
  await call(A, 'friend_extra', { p_title: '   ', p_badges: '' });
  [p] = sql('SELECT title, badges FROM friend_profiles WHERE user_id = ?', A);
  assert.deepEqual({ ...p }, { title: null, badges: null });
  await call(A, 'friend_extra', { p_title: 'champion', p_badges: 'y'.repeat(2100) });
  assert.equal(sql('SELECT badges FROM friend_profiles WHERE user_id = ?', A)[0].badges.length, 2000);
  assert.deepEqual(sql('SELECT title, badges FROM friend_profiles WHERE user_id = ?', B).map((r) => ({ ...r })), [{ title: null, badges: null }]);
});

// ── friend_respond en friend_remove ──

test('friend_respond: alleen wie het verzoek kreeg, kan het aanvaarden of weigeren', async () => {
  const { call, sql, sent, befriend } = setup();
  await profiles(call);
  befriend(A, B, 0);
  // De afzender zelf of een derde kan het verzoek niet aanvaarden
  await call(A, 'friend_respond', { p_other: B, p_accept: true });
  await call(C, 'friend_respond', { p_other: A, p_accept: true });
  assert.equal(sql('SELECT accepted FROM friendships')[0].accepted, 0);
  assert.equal(await call(B, 'friend_respond', { p_other: A, p_accept: true }), null);
  assert.equal(sql('SELECT accepted FROM friendships')[0].accepted, 1);
  assert.deepEqual(sent, [[A, { type: 'social' }]]);
  // Weigeren wist geen bestaande vriendschap
  await call(B, 'friend_respond', { p_other: A, p_accept: false });
  assert.equal(sql('SELECT count(*) AS n FROM friendships')[0].n, 1);
  befriend(C, B, 0);
  await call(A, 'friend_respond', { p_other: C, p_accept: false });
  assert.equal(sql('SELECT count(*) AS n FROM friendships WHERE requester = ?', C)[0].n, 1, 'een derde weigert niets');
  await call(B, 'friend_respond', { p_other: C, p_accept: false });
  assert.equal(sql('SELECT count(*) AS n FROM friendships WHERE requester = ?', C)[0].n, 0);
});

test('friend_remove: wist de vriendschap in beide richtingen, maar niet die van anderen', async () => {
  const { call, sql, befriend } = setup();
  befriend(A, B);
  befriend(C, A, 0);
  befriend(B, C);
  assert.equal(await call(B, 'friend_remove', { p_other: A }), null);
  await call(A, 'friend_remove', { p_other: C });
  assert.deepEqual(sql('SELECT requester, addressee FROM friendships').map((r) => ({ ...r })), [{ requester: B, addressee: C }]);
  await call(A, 'friend_remove', { p_other: B });
  await call(A, 'friend_remove', { p_other: null });
  assert.equal(sql('SELECT count(*) AS n FROM friendships')[0].n, 1, 'A kan de vriendschap van B en C niet wissen');
});

// ── Blokkeren ──

test('friend_block: vriendschap, open en lopende battles en open uitnodigingen weg; afgelopen battles blijven', async () => {
  const { call, sql, sent, befriend } = setup();
  await profiles(call);
  befriend(A, B);
  befriend(A, C);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted) VALUES ('old', '2026-10-12', ?, ?, 1)", A, B);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted) VALUES ('now', ?, ?, ?, 1)", WEEK, B, A);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted) VALUES ('open', '2026-10-05', ?, ?, 0)", A, B);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted) VALUES ('other', ?, ?, ?, 0)", WEEK, A, C);
  sql("INSERT INTO challenges (id, owner, template, nutrient, rule, days, need, start_day) VALUES ('c1', ?, 'custom', 'fiber', 'min', 7, 7, ?)", A, WEEK);
  sql("INSERT INTO challenge_members (challenge_id, user_id, invited_by, accepted) VALUES ('c1', ?, ?, 0), ('c1', ?, ?, 0)", B, A, C, A);
  assert.equal(await call(B, 'friend_block', { p_other: A }), null);
  assert.deepEqual(sql('SELECT requester, addressee FROM friendships').map((r) => ({ ...r })), [{ requester: A, addressee: C }]);
  assert.deepEqual(sql('SELECT id FROM battles ORDER BY id').map((r) => r.id), ['old', 'other']);
  assert.deepEqual(sql('SELECT user_id FROM challenge_members').map((r) => r.user_id), [C]);
  assert.equal(sent.length, 0, 'wie geblokkeerd wordt, krijgt geen seintje');
  // Nog eens blokkeren is geen fout
  await call(B, 'friend_block', { p_other: A });
  assert.equal(sql('SELECT count(*) AS n FROM user_blocks')[0].n, 1);
});

test('friend_block: jezelf, null of een onbekende gebruiker doet niets', async () => {
  const { call, sql } = setup();
  await call(A, 'friend_block', { p_other: A });
  await call(A, 'friend_block', { p_other: null });
  await call(A, 'friend_block', { p_other: '99999999-0000-4000-8000-000000000009' });
  assert.equal(sql('SELECT count(*) AS n FROM user_blocks')[0].n, 0);
});

test('friend_block: hoogstens 1000 blokkades', async () => {
  const { db, call, sql } = setup();
  const ins = db.raw.prepare('INSERT INTO user_blocks (blocker, blocked) VALUES (?, ?)');
  for (let i = 0; i < 1000; i++) {
    const u = `eeeeeeee-0000-4000-8000-${String(i).padStart(12, '0')}`;
    addUser(db, u);
    ins.run(A, u);
  }
  await fails(call(A, 'friend_block', { p_other: B }), 'P0001', 'te veel blokkades');
  assert.equal(sql('SELECT count(*) AS n FROM user_blocks WHERE blocked = ?', B)[0].n, 0);
});

test('friend_blocked_list en friend_unblock: alleen je eigen blokkades, nieuwste eerst', async () => {
  const { call, sql } = setup();
  await profiles(call);
  sql("UPDATE friend_profiles SET avatar = 'avC' WHERE user_id = ?", C);
  await call(A, 'friend_block', { p_other: B }, new Date('2026-10-28T10:00:00.000Z'));
  await call(A, 'friend_block', { p_other: C }, new Date('2026-10-28T11:00:00.000Z'));
  await call(D, 'friend_block', { p_other: A });
  assert.deepEqual(await call(A, 'friend_blocked_list'), [
    { other: C, name: 'Cleo', avatar: 'avC', created_at: '2026-10-28T11:00:00.000Z' },
    { other: B, name: 'Bob', avatar: null, created_at: '2026-10-28T10:00:00.000Z' },
  ]);
  // Wie geblokkeerd is, ziet niet wie hem blokkeerde
  assert.deepEqual(await call(B, 'friend_blocked_list'), []);
  // Een ander kan jouw blokkade niet opheffen
  await call(B, 'friend_unblock', { p_other: A });
  await call(D, 'friend_unblock', { p_other: B });
  assert.equal((await call(A, 'friend_blocked_list')).length, 2);
  assert.equal(await call(A, 'friend_unblock', { p_other: B }), null);
  assert.deepEqual((await call(A, 'friend_blocked_list')).map((r) => r.other), [C]);
  assert.equal(sql('SELECT count(*) AS n FROM friendships')[0].n, 0, 'na opheffen geen vrienden');
});

// ── Melden ──

test('friend_report: alleen wie een band met je heeft, met naam en avatar van dat moment', async () => {
  const { call, sql, befriend } = setup();
  await profiles(call);
  sql("UPDATE friend_profiles SET avatar = 'avB' WHERE user_id = ?", B);
  befriend(B, A, 0);
  assert.equal(await call(A, 'friend_report', { p_other: B, p_reason: 'nonsense', p_note: null }), 'bad_reason');
  assert.equal(await call(A, 'friend_report', { p_other: B, p_reason: null, p_note: null }), 'bad_reason');
  assert.equal(await call(A, 'friend_report', { p_other: B, p_reason: 'challenge_title', p_note: null }), 'bad_reason');
  assert.equal(await call(A, 'friend_report', { p_other: A, p_reason: 'spam', p_note: null }), 'not_found');
  assert.equal(await call(A, 'friend_report', { p_other: null, p_reason: 'spam', p_note: null }), 'not_found');
  assert.equal(await call(A, 'friend_report', { p_other: C, p_reason: 'spam', p_note: null }), 'not_found', 'een vreemde meld je niet');
  assert.equal(await call(A, 'friend_report', { p_other: B, p_reason: 'harassment', p_note: `  ${'n'.repeat(600)}` }), 'reported');
  const [r] = sql('SELECT * FROM user_reports');
  assert.equal(r.reporter, A);
  assert.equal(r.reported, B);
  assert.equal(r.reason, 'harassment');
  assert.equal(r.note, 'n'.repeat(500));
  assert.equal(r.reported_name, 'Bob');
  assert.equal(r.reported_avatar, 'avB');
  assert.equal(r.created_at, NOW.toISOString());
  // Ook na een blokkade, na een battle, of als medespeler in een uitdaging (zonder vriend te zijn)
  sql('DELETE FROM friendships');
  sql('INSERT INTO user_blocks (blocker, blocked) VALUES (?, ?)', A, B);
  assert.equal(await call(A, 'friend_report', { p_other: B, p_reason: 'spam', p_note: '' }), 'reported');
  assert.equal(sql('SELECT note FROM user_reports ORDER BY rowid DESC LIMIT 1')[0].note, null);
  assert.equal(await call(B, 'friend_report', { p_other: A, p_reason: 'spam' }), 'not_found', 'wie geblokkeerd is, kan niet melden via die blokkade');
  sql("INSERT INTO battles (id, week, challenger, opponent) VALUES ('b1', ?, ?, ?)", WEEK, C, A);
  assert.equal(await call(A, 'friend_report', { p_other: C, p_reason: 'other' }), 'reported');
  sql("INSERT INTO challenges (id, owner, template, nutrient, rule, days, need, start_day) VALUES ('c1', ?, 'custom', 'fiber', 'min', 7, 7, ?)", D, WEEK);
  sql("INSERT INTO challenge_members (challenge_id, user_id, accepted) VALUES ('c1', ?, 1), ('c1', ?, 0)", D, B);
  assert.equal(await call(B, 'friend_report', { p_other: D, p_reason: 'inappropriate' }), 'reported');
});

test('friend_report: hoogstens 10 meldingen per 24 uur', async () => {
  const { call, sql, befriend } = setup();
  befriend(A, B);
  sql("INSERT INTO user_reports (id, reporter, reported, reason, created_at) VALUES ('old', ?, ?, 'spam', '2026-10-27T11:00:00.000Z')", A, B);
  for (let i = 0; i < 10; i++) assert.equal(await call(A, 'friend_report', { p_other: B, p_reason: 'spam' }), 'reported');
  assert.equal(await call(A, 'friend_report', { p_other: B, p_reason: 'spam' }), 'limit');
  // Een dag later weer
  assert.equal(await call(A, 'friend_report', { p_other: B, p_reason: 'spam' }, new Date('2026-10-29T12:00:01.000Z')), 'reported');
  // De limiet is per melder
  assert.equal(await call(B, 'friend_report', { p_other: A, p_reason: 'spam' }), 'reported');
});

// ── Battles ──

test('battle_challenge: bad_week, not_friends, created (met seintje), exists en accepted', async () => {
  const { call, sql, sent, befriend } = setup();
  befriend(A, B);
  befriend(A, C, 0);
  assert.equal(await call(A, 'battle_challenge', { p_other: B, p_week: '2026-10-27' }), 'bad_week', 'geen maandag');
  assert.equal(await call(A, 'battle_challenge', { p_other: B, p_week: PREV }), 'bad_week', 'meer dan 8 dagen terug');
  assert.equal(await call(A, 'battle_challenge', { p_other: B, p_week: '2026-11-09' }), 'bad_week', 'meer dan 7 dagen vooruit');
  assert.equal(await call(A, 'battle_challenge', { p_other: B, p_week: null }), 'bad_week');
  assert.equal(await call(A, 'battle_challenge', { p_other: C, p_week: WEEK }), 'not_friends', 'een verzoek is nog geen vriendschap');
  assert.equal(await call(A, 'battle_challenge', { p_other: D, p_week: WEEK }), 'not_friends');
  assert.equal(await call(A, 'battle_challenge', { p_other: A, p_week: WEEK }), 'not_friends');
  assert.equal(sent.length, 0);
  assert.equal(await call(A, 'battle_challenge', { p_other: B, p_week: WEEK }), 'created');
  assert.deepEqual(sent, [[B, { type: 'social' }]]);
  assert.equal(await call(A, 'battle_challenge', { p_other: B, p_week: WEEK }), 'exists');
  assert.equal(await call(A, 'battle_challenge', { p_other: B, p_week: NEXT }), 'created', 'volgende week mag ook');
  assert.equal(await call(B, 'battle_challenge', { p_other: A, p_week: WEEK }), 'accepted', 'wie al uitgedaagd werd, aanvaardt');
  assert.deepEqual(sent.at(-1), [A, { type: 'social' }]);
  assert.equal(await call(B, 'battle_challenge', { p_other: A, p_week: WEEK }), 'exists');
  assert.equal(await call(A, 'battle_challenge', { p_other: B, p_week: WEEK }), 'exists');
  assert.deepEqual(sql('SELECT week, challenger, opponent, accepted FROM battles ORDER BY week').map((r) => ({ ...r })), [
    { week: WEEK, challenger: A, opponent: B, accepted: 1 },
    { week: NEXT, challenger: A, opponent: B, accepted: 0 },
  ]);
  // Op dinsdag mag de vorige week nog (8 dagen terug)
  assert.equal(await call(A, 'battle_challenge', { p_other: B, p_week: PREV }, new Date('2026-10-27T01:00:00.000Z')), 'created');
});

test('battle_respond: alleen wie uitgedaagd werd, aanvaardt of weigert; weigeren wist geen aanvaarde battle', async () => {
  const { call, sql, sent } = setup();
  sql("INSERT INTO battles (id, week, challenger, opponent) VALUES ('11111111-1111-4111-8111-111111111111', ?, ?, ?)", WEEK, A, B);
  const id = '11111111-1111-4111-8111-111111111111';
  await call(A, 'battle_respond', { p_id: id, p_accept: true });
  await call(C, 'battle_respond', { p_id: id, p_accept: true });
  await call(C, 'battle_respond', { p_id: id, p_accept: false });
  assert.equal(sql('SELECT accepted FROM battles')[0].accepted, 0);
  assert.equal(sent.length, 0);
  assert.equal(await call(B, 'battle_respond', { p_id: id, p_accept: true }), null);
  assert.equal(sql('SELECT accepted FROM battles')[0].accepted, 1);
  assert.deepEqual(sent, [[A, { type: 'social' }]]);
  await call(B, 'battle_respond', { p_id: id, p_accept: false });
  assert.equal(sql('SELECT count(*) AS n FROM battles')[0].n, 1);
  sql("UPDATE battles SET accepted = 0");
  await call(B, 'battle_respond', { p_id: id, p_accept: false });
  assert.equal(sql('SELECT count(*) AS n FROM battles')[0].n, 0);
  assert.equal(sent.length, 2, 'ook een weigering geeft de uitdager een seintje');
});

test('battle_cancel: alleen je eigen uitdaging, en alleen zolang ze niet aanvaard is', async () => {
  const { call, sql, sent } = setup();
  const id1 = '11111111-1111-4111-8111-111111111111', id2 = '22222222-2222-4222-8222-222222222222';
  sql('INSERT INTO battles (id, week, challenger, opponent, accepted) VALUES (?, ?, ?, ?, 0), (?, ?, ?, ?, 1)', id1, WEEK, A, B, id2, NEXT, A, B);
  await call(B, 'battle_cancel', { p_id: id1 });
  await call(C, 'battle_cancel', { p_id: id1 });
  await call(A, 'battle_cancel', { p_id: id2 });
  assert.equal(sql('SELECT count(*) AS n FROM battles')[0].n, 2);
  assert.equal(await call(A, 'battle_cancel', { p_id: id1 }), null);
  assert.deepEqual(sql('SELECT id FROM battles').map((r) => r.id), [id2]);
  assert.deepEqual(sent, [[B, { type: 'social' }]]);
});

test('battle_list: vorm en types, punten van beide kanten, nieuwste week eerst, oude open uitdagingen niet', async () => {
  const { call, sql } = setup();
  await profiles(call);
  sql("UPDATE friend_profiles SET avatar = 'avB', level = 4, title = 'champion' WHERE user_id = ?", B);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted, created_at) VALUES ('b-now', ?, ?, ?, 1, '2026-10-26T08:00:00.000Z')", WEEK, A, B);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted, created_at) VALUES ('c-now', ?, ?, ?, 0, '2026-10-26T09:00:00.000Z')", WEEK, C, A);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted, created_at) VALUES ('b-old', '2026-09-07', ?, ?, 1, '2026-09-07T08:00:00.000Z')", B, A);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted, created_at) VALUES ('c-stale', '2026-10-12', ?, ?, 0, '2026-10-12T08:00:00.000Z')", C, A);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted, created_at) VALUES ('c-edge', '2026-10-19', ?, ?, 0, '2026-10-19T08:00:00.000Z')", A, C);
  sql("INSERT INTO battles (id, week, challenger, opponent, accepted) VALUES ('other', ?, ?, ?, 1)", WEEK, B, C);
  sql('INSERT INTO weekly_scores (user_id, week, score, days, points, mid_points) VALUES (?, ?, 50, 3, 150, 120)', A, WEEK);
  sql('INSERT INTO weekly_scores (user_id, week, score, days, points, mid_points) VALUES (?, ?, 70, 3, 210, 90)', B, WEEK);
  const rows = await call(A, 'battle_list');
  assert.deepEqual(rows.map((r) => r.id), ['c-now', 'b-now', 'c-edge', 'b-old']);
  assert.deepEqual(rows[1], {
    id: 'b-now', week: WEEK, challenged_by_me: true, accepted: true, other: B, other_name: 'Bob', other_avatar: 'avB', other_level: 4,
    other_title: 'champion', my_points: 150, my_mid: 120, other_points: 210, other_mid: 90,
  });
  assert.deepEqual(rows[0], {
    id: 'c-now', week: WEEK, challenged_by_me: false, accepted: false, other: C, other_name: 'Cleo', other_avatar: null, other_level: 1,
    other_title: null, my_points: 150, my_mid: 120, other_points: 0, other_mid: 0,
  });
  // De battle van B en C ziet A niet; D heeft er geen
  assert.ok(!rows.some((r) => r.id === 'other'));
  assert.deepEqual(await call(D, 'battle_list'), []);
});
