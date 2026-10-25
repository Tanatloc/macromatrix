// Uitdagingen (src/rpc/challenges.js): dezelfde controles en antwoorden als de security-definer-functies en de
// RLS op challenge_days in Supabase. Overgenomen uit supabase/tests/moderation_test.mjs, aangevuld per tak.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import './workers-stub.mjs';
import { addUser, d1 } from './d1.mjs';
import challenges from '../src/rpc/challenges.js';
import { fromD1 } from '../src/errors.js';

const { callRpc } = await import('../src/rpc/index.js');

const NOW = new Date('2026-10-25T12:00:00Z');
const TODAY = '2026-10-25';
const day = (n) => new Date(Date.parse(`${TODAY}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);

const call = (db, uid, name, params = {}, now = NOW) => callRpc(name, params, { db, env: {}, uid, now });

/** Rechtstreeks de functie, met een ctx die de seintjes bijhoudt. */
async function direct(db, uid, name, params = {}, now = NOW) {
  const sent = [];
  const result = await challenges[name]({ db, uid, now, env: {}, notify: (to, msg) => sent.push([to, msg]) }, params);
  return { result, sent };
}

const befriend = (db, a, b, accepted = 1) =>
  db.raw.prepare('INSERT INTO friendships (requester, addressee, accepted) VALUES (?, ?, ?)').run(a, b, accepted);
const profile = (db, uid, name, extra = {}) =>
  db.raw.prepare('INSERT INTO friend_profiles (user_id, code, name, avatar, level) VALUES (?, ?, ?, ?, ?)').run(uid, `code-${uid}`, name, extra.avatar ?? null, extra.level ?? 1);
const block = (db, a, b) => db.raw.prepare('INSERT INTO user_blocks (blocker, blocked) VALUES (?, ?)').run(a, b);
const members = (db, id) => db.raw.prepare('SELECT user_id, accepted, invited_by FROM challenge_members WHERE challenge_id = ? ORDER BY rowid').all(id).map((r) => ({ ...r }));
const daysOf = (db, id, uid) => db.raw.prepare('SELECT day, met, updated_at FROM challenge_days WHERE challenge_id = ? AND user_id = ? ORDER BY day').all(id, uid).map((r) => ({ ...r }));

const base = (extra = {}) => ({
  p_template: 'custom', p_title: 'Vezelweek', p_nutrient: 'fiber', p_rule: 'min', p_amount: 25, p_days: 14, p_need: 10, p_start: TODAY, p_invite: [], ...extra,
});

// a en b vrienden, b en c vrienden, a en c niet; d staat erbuiten
function setup() {
  const db = d1();
  for (const u of ['a', 'b', 'c', 'd']) addUser(db, u);
  profile(db, 'a', 'Anna', { avatar: 'av-a', level: 7 });
  profile(db, 'b', 'Bob');
  profile(db, 'c', 'Cleo');
  befriend(db, 'a', 'b');
  befriend(db, 'c', 'b');
  return db;
}

/** Uitdaging van a met b als aanvaarde deelnemer. */
async function withGroup(db, extra = {}) {
  const id = await call(db, 'a', 'challenge_create', base({ p_invite: ['b'], ...extra }));
  await call(db, 'b', 'challenge_respond', { p_id: id, p_accept: true });
  return id;
}

// ── challenge_create ──

test('challenge_create: geeft een uuid, maker is aanvaard, alleen vrienden worden uitgenodigd (met seintje)', async () => {
  const db = setup();
  const { result: id, sent } = await direct(db, 'a', 'challenge_create', base({ p_invite: ['b', 'c', 'a', 'b', 'nobody', null] }));
  assert.match(id, /^[0-9a-f-]{36}$/);
  assert.deepEqual(members(db, id), [
    { user_id: 'a', accepted: 1, invited_by: 'a' },
    { user_id: 'b', accepted: 0, invited_by: 'a' },
  ]);
  assert.deepEqual(sent, [['b', { type: 'social' }]]);
  const c = db.raw.prepare('SELECT * FROM challenges WHERE id = ?').get(id);
  assert.equal(c.owner, 'a');
  assert.equal(c.title, 'Vezelweek');
  assert.equal(c.start_day, TODAY);
  assert.equal(c.created_at, NOW.toISOString());
});

test('challenge_create: titel wordt getrimd en op 60 tekens afgekapt, leeg wordt null, amount null wordt 0', async () => {
  const db = setup();
  const id1 = await call(db, 'a', 'challenge_create', base({ p_title: `  ${'é'.repeat(70)}  ` }));
  assert.equal(db.raw.prepare('SELECT title FROM challenges WHERE id = ?').get(id1).title, 'é'.repeat(60));
  const id2 = await call(db, 'a', 'challenge_create', base({ p_title: '   ', p_amount: null }));
  const c = db.raw.prepare('SELECT title, amount FROM challenges WHERE id = ?').get(id2);
  assert.equal(c.title, null);
  assert.equal(c.amount, 0);
  assert.ok(await call(db, 'a', 'challenge_create', base({ p_title: null, p_invite: null })));
});

test('challenge_create: scheldtitel geweigerd met title_not_allowed (22023) en een hint', async () => {
  const db = setup();
  await assert.rejects(call(db, 'a', 'challenge_create', base({ p_title: 'Kut uitdaging' })), { code: '22023', message: 'title_not_allowed', hint: 'Kies een andere titel.' });
  assert.equal(db.raw.prepare('SELECT count(*) n FROM challenges').get().n, 0);
});

test('challenge_create: startdag van gisteren tot over 14 dagen', async () => {
  const db = setup();
  assert.ok(await call(db, 'a', 'challenge_create', base({ p_start: day(-1) })));
  assert.ok(await call(db, 'a', 'challenge_create', base({ p_start: day(14) })));
  for (const s of [day(-2), day(15)])
    await assert.rejects(call(db, 'a', 'challenge_create', base({ p_start: s })), { code: 'P0001', message: 'startdag buiten bereik' });
  await assert.rejects(call(db, 'a', 'challenge_create', base({ p_start: '25-10-2026' })), { code: '22007' });
  await assert.rejects(call(db, 'a', 'challenge_create', base({ p_start: '2026-02-30' })), { code: '22007' });
});

test('challenge_create: hoogstens 20 lopende uitdagingen; afgelopen tellen niet mee', async () => {
  const db = setup();
  for (let i = 0; i < 20; i++) await call(db, 'a', 'challenge_create', base());
  await assert.rejects(call(db, 'a', 'challenge_create', base()), { code: 'P0001', message: 'te veel lopende uitdagingen' });
  assert.equal(db.raw.prepare('SELECT count(*) n FROM challenges').get().n, 20);
  // Een maand later zijn ze afgelopen (start + 14 dagen < vandaag)
  assert.ok(await call(db, 'a', 'challenge_create', base({ p_start: '2026-11-30' }), new Date('2026-11-30T08:00:00Z')));
});

test('challenge_create: hoogstens 20 deelnemers bij het aanmaken', async () => {
  const db = setup();
  const many = Array.from({ length: 25 }, (_, i) => `f${i}`);
  for (const f of many) {
    addUser(db, f);
    befriend(db, 'a', f);
  }
  const id = await call(db, 'a', 'challenge_create', base({ p_invite: many }));
  assert.equal(members(db, id).length, 20);
});

test('challenge_create: ongeldige waarden geven de fout van Postgres en schrijven niets', async () => {
  const db = setup();
  const bad = async (extra, code) => {
    let err;
    try {
      await call(db, 'a', 'challenge_create', base(extra));
    } catch (e) {
      err = fromD1(e);
    }
    assert.equal(err?.code, code, JSON.stringify(extra));
  };
  await bad({ p_rule: 'zoveel' }, '23514');
  await bad({ p_days: 91, p_need: 10 }, '23514');
  await bad({ p_need: 20 }, '23514'); // need > days
  await bad({ p_days: null }, '23502');
  await bad({ p_start: null }, '23502');
  await bad({ p_days: 1.5 }, '22P02');
  await bad({ p_amount: 'veel' }, '22P02');
  await bad({ p_invite: 'b' }, '22P02');
  await bad({ p_invite: [5] }, '22P02');
  assert.equal(db.raw.prepare('SELECT count(*) n FROM challenges').get().n, 0);
  assert.equal(db.raw.prepare('SELECT count(*) n FROM challenge_members').get().n, 0);
  // Getallen als tekst neemt Postgres ook aan
  assert.ok(await call(db, 'a', 'challenge_create', base({ p_days: '14', p_need: '7', p_amount: '2.5' })));
});

// ── challenge_invite ──

test('challenge_invite: invited met seintje, daarna exists', async () => {
  const db = setup();
  const id = await withGroup(db);
  const { result, sent } = await direct(db, 'b', 'challenge_invite', { p_id: id, p_other: 'c' });
  assert.equal(result, 'invited');
  assert.deepEqual(sent, [['c', { type: 'social' }]]);
  assert.deepEqual(members(db, id).at(-1), { user_id: 'c', accepted: 0, invited_by: 'b' });
  const again = await direct(db, 'b', 'challenge_invite', { p_id: id, p_other: 'c' });
  assert.deepEqual(again, { result: 'exists', sent: [] });
});

test('challenge_invite: not_member voor buitenstaanders en wie nog niet aanvaardde', async () => {
  const db = setup();
  const id = await call(db, 'a', 'challenge_create', base({ p_invite: ['b'] }));
  befriend(db, 'd', 'c');
  assert.equal(await call(db, 'd', 'challenge_invite', { p_id: id, p_other: 'c' }), 'not_member');
  assert.equal(await call(db, 'b', 'challenge_invite', { p_id: id, p_other: 'c' }), 'not_member');
  assert.equal(await call(db, 'a', 'challenge_invite', { p_id: '00000000-0000-0000-0000-000000000000', p_other: 'b' }), 'not_member');
  assert.equal(await call(db, 'a', 'challenge_invite', { p_id: null, p_other: 'b' }), 'not_member');
  assert.equal(members(db, id).length, 2);
});

test('challenge_invite: not_friends (ook een openstaand vriendschapsverzoek) en finished', async () => {
  const db = setup();
  const id = await call(db, 'a', 'challenge_create', base({ p_days: 3, p_need: 3 }));
  assert.equal(await call(db, 'a', 'challenge_invite', { p_id: id, p_other: 'c' }), 'not_friends');
  befriend(db, 'a', 'd', 0);
  assert.equal(await call(db, 'a', 'challenge_invite', { p_id: id, p_other: 'd' }), 'not_friends');
  assert.equal(await call(db, 'a', 'challenge_invite', { p_id: id, p_other: null }), 'not_friends');
  // Op de laatste dag kan het nog, de dag erna is ze afgelopen
  assert.equal(await call(db, 'a', 'challenge_invite', { p_id: id, p_other: 'b' }, new Date(`${day(2)}T23:00:00Z`)), 'invited');
  befriend(db, 'a', 'c');
  assert.equal(await call(db, 'a', 'challenge_invite', { p_id: id, p_other: 'c' }, new Date(`${day(3)}T00:00:00Z`)), 'finished');
});

test('challenge_invite: full bij 20 deelnemers (uitgenodigd telt mee)', async () => {
  const db = setup();
  const id = await call(db, 'a', 'challenge_create', base());
  for (let i = 0; i < 20; i++) {
    addUser(db, `f${i}`);
    befriend(db, 'a', `f${i}`);
  }
  for (let i = 0; i < 19; i++) assert.equal(await call(db, 'a', 'challenge_invite', { p_id: id, p_other: `f${i}` }), 'invited');
  assert.equal(await call(db, 'a', 'challenge_invite', { p_id: id, p_other: 'f19' }), 'full');
  assert.equal(await call(db, 'a', 'challenge_invite', { p_id: id, p_other: 'f0' }), 'exists');
  assert.equal(members(db, id).length, 20);
});

test('challenge_invite: een ongeldig id geeft 22P02', async () => {
  const db = setup();
  await assert.rejects(call(db, 'a', 'challenge_invite', { p_id: 'geen-uuid', p_other: 'b' }), { code: '22P02' });
});

// ── challenge_respond ──

test('challenge_respond: aannemen geeft null en een seintje aan wie uitnodigde', async () => {
  const db = setup();
  const id = await call(db, 'a', 'challenge_create', base({ p_invite: ['b'] }));
  const r = await direct(db, 'b', 'challenge_respond', { p_id: id, p_accept: true });
  assert.deepEqual(r, { result: null, sent: [['a', { type: 'social' }]] });
  assert.equal(members(db, id)[1].accepted, 1);
  // Nog eens aannemen verandert niets en stuurt niets
  assert.deepEqual(await direct(db, 'b', 'challenge_respond', { p_id: id, p_accept: true }), { result: null, sent: [] });
});

test('challenge_respond: weigeren haalt alleen een openstaande uitnodiging weg; null telt als weigeren', async () => {
  const db = setup();
  befriend(db, 'a', 'c');
  const id = await call(db, 'a', 'challenge_create', base({ p_invite: ['b', 'c'] }));
  assert.deepEqual(await direct(db, 'b', 'challenge_respond', { p_id: id, p_accept: false }), { result: null, sent: [['a', { type: 'social' }]] });
  assert.equal(await call(db, 'c', 'challenge_respond', { p_id: id, p_accept: null }), null);
  assert.deepEqual(members(db, id).map((m) => m.user_id), ['a']);
  // Wie al meedoet, verdwijnt niet door te weigeren
  assert.equal(await call(db, 'a', 'challenge_respond', { p_id: id, p_accept: false }), null);
  assert.deepEqual(members(db, id).map((m) => m.user_id), ['a']);
});

test('challenge_respond: een buitenstaander kan zichzelf niet toevoegen of een ander aannemen', async () => {
  const db = setup();
  const id = await call(db, 'a', 'challenge_create', base({ p_invite: ['b'] }));
  await call(db, 'd', 'challenge_respond', { p_id: id, p_accept: true });
  assert.deepEqual(members(db, id), [
    { user_id: 'a', accepted: 1, invited_by: 'a' },
    { user_id: 'b', accepted: 0, invited_by: 'a' },
  ]);
  await assert.rejects(call(db, 'b', 'challenge_respond', { p_id: id, p_accept: 'misschien' }), { code: '22P02' });
});

// ── challenge_leave ──

test('challenge_leave: je dagen en je plaats weg, de uitdaging blijft voor de anderen', async () => {
  const db = setup();
  const id = await withGroup(db);
  await call(db, 'a', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: true } });
  await call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: true } });
  assert.equal(await call(db, 'b', 'challenge_leave', { p_id: id }), null);
  assert.deepEqual(members(db, id).map((m) => m.user_id), ['a']);
  assert.equal(daysOf(db, id, 'b').length, 0);
  assert.equal(daysOf(db, id, 'a').length, 1);
});

test('challenge_leave: laatste aanvaarde deelnemer weg, dan verdwijnt de uitdaging (met openstaande uitnodigingen)', async () => {
  const db = setup();
  const id = await call(db, 'a', 'challenge_create', base({ p_invite: ['b'] }));
  await call(db, 'a', 'challenge_leave', { p_id: id });
  assert.equal(db.raw.prepare('SELECT count(*) n FROM challenges').get().n, 0);
  assert.equal(db.raw.prepare('SELECT count(*) n FROM challenge_members').get().n, 0);
});

test('challenge_leave: een buitenstaander verandert niets', async () => {
  const db = setup();
  const id = await withGroup(db);
  await call(db, 'a', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: true } });
  await call(db, 'd', 'challenge_leave', { p_id: id });
  assert.equal(members(db, id).length, 2);
  assert.equal(daysOf(db, id, 'a').length, 1);
});

// ── challenge_list ──

test('challenge_list: één rij per deelnemer, kolommen in de volgorde van Supabase, met de juiste types', async () => {
  const db = setup();
  const id = await withGroup(db);
  await call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: true, [day(1)]: false } });
  const rows = await call(db, 'b', 'challenge_list');
  assert.equal(rows.length, 2);
  assert.deepEqual(Object.keys(rows[0]), [
    'id', 'template', 'title', 'nutrient', 'rule', 'amount', 'days', 'need', 'start_day', 'owner_is_me', 'invited_by_name',
    'member', 'member_name', 'member_avatar', 'member_level', 'member_accepted', 'member_met', 'is_me',
  ]);
  assert.deepEqual(rows[0], {
    id, template: 'custom', title: 'Vezelweek', nutrient: 'fiber', rule: 'min', amount: 25, days: 14, need: 10, start_day: TODAY,
    owner_is_me: false, invited_by_name: 'Anna', member: 'a', member_name: 'Anna', member_avatar: 'av-a', member_level: 7,
    member_accepted: true, member_met: 0, is_me: false,
  });
  assert.deepEqual(
    { member: rows[1].member, member_name: rows[1].member_name, member_avatar: rows[1].member_avatar, member_level: rows[1].member_level, member_met: rows[1].member_met, is_me: rows[1].is_me },
    { member: 'b', member_name: 'Bob', member_avatar: null, member_level: 1, member_met: 1, is_me: true },
  );
  const mine = await call(db, 'a', 'challenge_list');
  assert.equal(mine[0].owner_is_me, true);
  assert.equal(mine[0].invited_by_name, 'Anna');
});

test('challenge_list: uitgenodigden zien de uitdaging; buitenstaanders zien niets', async () => {
  const db = setup();
  const id = await call(db, 'a', 'challenge_create', base({ p_invite: ['b'] }));
  const rows = await call(db, 'b', 'challenge_list');
  assert.deepEqual(rows.map((r) => [r.member, r.member_accepted]), [['a', true], ['b', false]]);
  assert.ok(rows.every((r) => r.id === id));
  assert.deepEqual(await call(db, 'd', 'challenge_list'), []);
  assert.deepEqual(await call(db, 'c', 'challenge_list'), []);
});

test('challenge_list: zonder profiel lege naam en niveau 1; volgorde nieuwste start eerst', async () => {
  const db = setup();
  befriend(db, 'a', 'd');
  const older = await call(db, 'a', 'challenge_create', base({ p_start: day(-1), p_invite: ['d'] }));
  const newer = await call(db, 'a', 'challenge_create', base({ p_start: day(3) }));
  const rows = await call(db, 'a', 'challenge_list');
  assert.deepEqual(rows.map((r) => r.id), [newer, older, older]);
  assert.deepEqual([rows[2].member, rows[2].member_name, rows[2].member_level], ['d', '', 1]);
  const asD = await call(db, 'd', 'challenge_list');
  assert.equal(asD[0].invited_by_name, 'Anna');
});

test('challenge_list: tot 60 dagen na het einde', async () => {
  const db = setup();
  await call(db, 'a', 'challenge_create', base());
  const end = Date.parse(`${TODAY}T00:00:00Z`) + 14 * 86_400_000;
  assert.equal((await call(db, 'a', 'challenge_list', {}, new Date(end + 60 * 86_400_000))).length, 1);
  assert.equal((await call(db, 'a', 'challenge_list', {}, new Date(end + 61 * 86_400_000))).length, 0);
});

test('challenge_list: blokkeren verbergt de ander in beide richtingen, de rest blijft', async () => {
  const db = setup();
  const id = await withGroup(db);
  await call(db, 'b', 'challenge_invite', { p_id: id, p_other: 'c' });
  await call(db, 'c', 'challenge_respond', { p_id: id, p_accept: true });
  const ids = async (u) => [...new Set((await call(db, u, 'challenge_list')).map((r) => r.member))];
  assert.deepEqual(await ids('c'), ['a', 'b', 'c']);
  block(db, 'c', 'a');
  assert.deepEqual(await ids('c'), ['b', 'c']);
  assert.deepEqual(await ids('a'), ['a', 'b']);
  assert.deepEqual(await ids('b'), ['a', 'b', 'c']);
});

// ── challenge_report ──

test('challenge_report: deelnemer meldt; de melding bewaart maker, uitdaging, titel en notitie', async () => {
  const db = setup();
  const id = await withGroup(db);
  assert.equal(await call(db, 'b', 'challenge_report', { p_id: id, p_note: '  rare titel  ' }), 'reported');
  const rep = db.raw.prepare('SELECT * FROM user_reports').get();
  assert.deepEqual(
    { reporter: rep.reporter, reported: rep.reported, reason: rep.reason, note: rep.note, challenge_id: rep.challenge_id, challenge_title: rep.challenge_title, reported_name: rep.reported_name, reported_avatar: rep.reported_avatar },
    { reporter: 'b', reported: 'a', reason: 'challenge_title', note: 'rare titel', challenge_id: id, challenge_title: 'Vezelweek', reported_name: 'Anna', reported_avatar: 'av-a' },
  );
});

test('challenge_report: zonder titel het sjabloon, lege notitie wordt null, notitie hoogstens 500 tekens', async () => {
  const db = setup();
  const id = await call(db, 'a', 'challenge_create', base({ p_title: null, p_template: 'fiber30', p_invite: ['b'] }));
  // Ook een uitgenodigde (nog niet aanvaard) mag melden
  assert.equal(await call(db, 'b', 'challenge_report', { p_id: id, p_note: '   ' }), 'reported');
  assert.equal(await call(db, 'b', 'challenge_report', { p_id: id, p_note: 'x'.repeat(600) }), 'reported');
  const reps = db.raw.prepare('SELECT note, challenge_title FROM user_reports ORDER BY rowid').all();
  assert.equal(reps[0].note, null);
  assert.equal(reps[0].challenge_title, 'fiber30');
  assert.equal(reps[1].note.length, 500);
});

test('challenge_report: not_found voor je eigen uitdaging, buitenstaanders en onbekende ids', async () => {
  const db = setup();
  const id = await withGroup(db);
  assert.equal(await call(db, 'a', 'challenge_report', { p_id: id, p_note: null }), 'not_found');
  assert.equal(await call(db, 'd', 'challenge_report', { p_id: id, p_note: null }), 'not_found');
  assert.equal(await call(db, 'b', 'challenge_report', { p_id: crypto.randomUUID() }), 'not_found');
  assert.equal(db.raw.prepare('SELECT count(*) n FROM user_reports').get().n, 0);
});

test('challenge_report: hoogstens 10 meldingen per 24 uur (ook andere meldingen tellen mee)', async () => {
  const db = setup();
  const id = await withGroup(db);
  db.raw.prepare("INSERT INTO user_reports (id, reporter, reported, reason, created_at) VALUES ('r0', 'b', 'c', 'spam', ?)").run(new Date(NOW.getTime() - 3_600_000).toISOString());
  // Een melding van meer dan een dag geleden telt niet
  db.raw.prepare("INSERT INTO user_reports (id, reporter, reported, reason, created_at) VALUES ('r1', 'b', 'c', 'spam', ?)").run(new Date(NOW.getTime() - 86_400_000).toISOString());
  for (let i = 0; i < 9; i++) assert.equal(await call(db, 'b', 'challenge_report', { p_id: id }), 'reported');
  assert.equal(await call(db, 'b', 'challenge_report', { p_id: id }), 'limit');
  assert.equal(await call(db, 'b', 'challenge_report', { p_id: id }, new Date(NOW.getTime() + 86_400_000)), 'reported');
});

// ── challenge_days_put ──

test('challenge_days_put: bewaart en werkt bij (upsert), met updated_at van de server', async () => {
  const db = setup();
  const id = await withGroup(db, { p_start: day(-1) });
  assert.equal(await call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [day(-1)]: true, [TODAY]: false, [day(1)]: true } }), null);
  assert.deepEqual(daysOf(db, id, 'b'), [
    { day: day(-1), met: 1, updated_at: NOW.toISOString() },
    { day: TODAY, met: 0, updated_at: NOW.toISOString() },
    { day: day(1), met: 1, updated_at: NOW.toISOString() },
  ]);
  const later = new Date(NOW.getTime() + 60_000);
  await call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: true } }, later);
  assert.deepEqual(daysOf(db, id, 'b')[1], { day: TODAY, met: 1, updated_at: later.toISOString() });
  assert.equal((await call(db, 'a', 'challenge_list')).find((r) => r.member === 'b').member_met, 3);
  assert.equal(await call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: {} }), null);
});

const RLS = { code: '42501', message: 'new row violates row-level security policy for table "challenge_days"' };

test('challenge_days_put: buitenstaander, uitgenodigde en onbekende uitdaging krijgen 42501', async () => {
  const db = setup();
  const id = await call(db, 'a', 'challenge_create', base({ p_invite: ['b'] }));
  await assert.rejects(call(db, 'd', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: true } }), RLS);
  await assert.rejects(call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: true } }), RLS);
  await assert.rejects(call(db, 'a', 'challenge_days_put', { p_challenge: crypto.randomUUID(), p_days: { [TODAY]: true } }), RLS);
  assert.equal(db.raw.prepare('SELECT count(*) n FROM challenge_days').get().n, 0);
});

test('challenge_days_put: een dag buiten de looptijd of na morgen weigert de hele aanroep', async () => {
  const db = setup();
  const id = await withGroup(db, { p_start: day(1), p_days: 3, p_need: 3 });
  // Voor de start, op start + days, en day(2): binnen de looptijd maar na morgen
  for (const bad of [TODAY, day(4), day(2)])
    await assert.rejects(call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [day(1)]: true, [bad]: true } }), RLS, bad);
  assert.equal(daysOf(db, id, 'b').length, 0);
  // Een dag later mag day(2) wel, day(4) (= start + days) nooit
  await call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [day(1)]: true, [day(2)]: true, [day(3)]: false } }, new Date(`${day(2)}T10:00:00Z`));
  assert.equal(daysOf(db, id, 'b').length, 3);
  await assert.rejects(call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [day(4)]: true } }, new Date(`${day(9)}T10:00:00Z`)), RLS);
});

test('challenge_days_put: je schrijft alleen je eigen rijen; een ander zijn dagen blijven staan', async () => {
  const db = setup();
  const id = await withGroup(db);
  await call(db, 'a', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: true } });
  // user_id in de invoer bestaat niet: b schrijft altijd als b
  await call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: false }, user_id: 'a' });
  assert.equal(daysOf(db, id, 'a')[0].met, 1);
  assert.equal(daysOf(db, id, 'b')[0].met, 0);
  await call(db, 'b', 'challenge_leave', { p_id: id });
  await assert.rejects(call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: true } }), RLS);
});

test('challenge_days_put: ongeldige invoer', async () => {
  const db = setup();
  const id = await withGroup(db);
  await assert.rejects(call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { 'gisteren': true } }), { code: '22007' });
  await assert.rejects(call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: { [TODAY]: null } }), { code: '23502' });
  await assert.rejects(call(db, 'b', 'challenge_days_put', { p_challenge: id, p_days: [true] }), { code: '22P02' });
  await assert.rejects(call(db, 'b', 'challenge_days_put', { p_challenge: 'x', p_days: { [TODAY]: true } }), { code: '22P02' });
  assert.equal(db.raw.prepare('SELECT count(*) n FROM challenge_days').get().n, 0);
});

test('zonder sessie: niet ingelogd (PGRST301)', async () => {
  const db = setup();
  for (const name of ['challenge_create', 'challenge_invite', 'challenge_respond', 'challenge_leave', 'challenge_list', 'challenge_report', 'challenge_days_put'])
    await assert.rejects(call(db, null, name, {}), { code: 'PGRST301' });
});
