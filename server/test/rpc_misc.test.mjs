// src/rpc/misc.js: dagtellers, Supporter, features, roadmap, meldingstokens en AI-meldingen, zoals in Supabase.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import './workers-stub.mjs';
import { addUser, d1 } from './d1.mjs';

const { callRpc } = await import('../src/rpc/index.js');

const NOW = new Date('2026-10-25T12:00:00.000Z');
const at = (iso) => new Date(iso);

function setup() {
  const db = d1();
  addUser(db, 'a');
  addUser(db, 'b');
  return db;
}

const rpc = (db, uid, name, params = {}, now = NOW) => callRpc(name, params, { db, env: {}, uid, now });

/** Een Supporter tot [until]. */
const makePro = (db, uid, until = '2027-01-01T00:00:00.000Z', extra = {}) =>
  db.raw
    .prepare('INSERT INTO pro_status (user_id, until, source, show_badge, frame) VALUES (?, ?, ?, ?, ?)')
    .run(uid, until, extra.source ?? 'manual', extra.show_badge ?? 1, extra.frame ?? null);

const fails = (promise, code, message) =>
  assert.rejects(promise, (e) => e.code === code && (message === undefined || e.message === message));

// ---- Dagtellers ----

test('ai_quota_use: gratis 1 label per dag, daarna geweigerd met dezelfde stand', async () => {
  const db = setup();
  assert.deepEqual(await rpc(db, 'a', 'ai_quota', { p_kind: 'label' }), { allowed: true, used: 0, limit: 1, pro: false });
  assert.deepEqual(await rpc(db, 'a', 'ai_quota_use', { p_kind: 'label' }), { allowed: true, used: 1, limit: 1, pro: false });
  assert.deepEqual(await rpc(db, 'a', 'ai_quota_use', { p_kind: 'label' }), { allowed: false, used: 1, limit: 1, pro: false });
  assert.deepEqual(await rpc(db, 'a', 'ai_quota', { p_kind: 'label' }), { allowed: false, used: 1, limit: 1, pro: false });
  // Een andere soort en een andere gebruiker hebben hun eigen teller
  assert.equal((await rpc(db, 'a', 'ai_quota_use', { p_kind: 'voice' })).used, 1);
  assert.equal((await rpc(db, 'b', 'ai_quota_use', { p_kind: 'label' })).allowed, true);
});

test('ai-limieten per soort, gratis tegenover Supporter', async () => {
  const db = setup();
  makePro(db, 'b');
  const lim = async (uid, kind) => (await rpc(db, uid, 'ai_quota', { p_kind: kind })).limit;
  assert.deepEqual(
    await Promise.all(['label', 'recipe', 'coach', 'voice', 'off', 'iets'].map((k) => lim('a', k))),
    [1, 0, 0, 60, 10, 0],
  );
  assert.deepEqual(
    await Promise.all(['label', 'recipe', 'coach', 'voice', 'off', 'iets'].map((k) => lim('b', k))),
    [30, 20, 3, 200, 10, 0],
  );
  assert.equal((await rpc(db, 'b', 'ai_quota', { p_kind: 'label' })).pro, true);
});

test('coach: gratis 1 per dag zodra de functie voor iedereen open is', async () => {
  const db = setup();
  db.raw.prepare("INSERT INTO features (id, title_en, title_nl, public_from) VALUES ('coach', 'Coach', 'Coach', '2026-11-01T00:00:00.000Z')").run();
  assert.equal((await rpc(db, 'a', 'ai_quota', { p_kind: 'coach' })).limit, 0);
  assert.equal((await rpc(db, 'a', 'ai_quota', { p_kind: 'coach' }, at('2026-11-01T00:00:00.000Z'))).limit, 1);
});

test('ai_quota_use: limiet 0 telt niets, onbekende soort is een fout', async () => {
  const db = setup();
  assert.deepEqual(await rpc(db, 'a', 'ai_quota_use', { p_kind: 'recipe' }), { allowed: false, used: 0, limit: 0, pro: false });
  assert.equal(db.raw.prepare('SELECT count(*) AS n FROM ai_usage').get().n, 0);
  await fails(rpc(db, 'a', 'ai_quota_use', { p_kind: 'photo' }), 'P0001', 'onbekende soort');
  await fails(rpc(db, 'a', 'ai_quota_use', {}), 'P0001', 'onbekende soort');
});

test('ai_quota_use: Supporter tot 30 labels, verzoeken tegelijk gaan niet over de grens', async () => {
  const db = setup();
  makePro(db, 'a');
  const r = await Promise.all(Array.from({ length: 40 }, () => rpc(db, 'a', 'ai_quota_use', { p_kind: 'label' })));
  assert.equal(r.filter((x) => x.allowed).length, 30);
  assert.deepEqual(r.filter((x) => x.allowed).map((x) => x.used).sort((x, y) => x - y), Array.from({ length: 30 }, (_, i) => i + 1));
  assert.ok(r.filter((x) => !x.allowed).every((x) => x.used === 30 && x.limit === 30));
});

test('dag is UTC: om middernacht UTC begint de teller opnieuw, oude dagen worden opgeruimd', async () => {
  const db = setup();
  assert.equal((await rpc(db, 'a', 'ai_quota_use', { p_kind: 'label' }, at('2026-10-25T23:59:59.000Z'))).allowed, true);
  assert.equal((await rpc(db, 'a', 'ai_quota_use', { p_kind: 'label' }, at('2026-10-25T23:59:59.900Z'))).allowed, false);
  assert.deepEqual(await rpc(db, 'a', 'ai_quota_use', { p_kind: 'label' }, at('2026-10-26T00:00:00.000Z')), { allowed: true, used: 1, limit: 1, pro: false });
  assert.equal((await rpc(db, 'a', 'photo_quota_use', {}, at('2026-10-26T00:00:00.000Z'))).used, 1);
  await rpc(db, 'a', 'ai_quota_use', { p_kind: 'label' }, at('2026-11-05T10:00:00.000Z'));
  assert.deepEqual(db.raw.prepare("SELECT day FROM ai_usage WHERE user_id = 'a' ORDER BY day").all().map((r) => r.day), ['2026-11-05']);
});

test('photo_quota: 3 gratis, 50 als Supporter; een verlopen abonnement telt niet', async () => {
  const db = setup();
  assert.deepEqual(await rpc(db, 'a', 'photo_quota'), { allowed: true, used: 0, limit: 3, pro: false });
  for (let i = 1; i <= 3; i++) assert.deepEqual(await rpc(db, 'a', 'photo_quota_use'), { allowed: true, used: i, limit: 3, pro: false });
  assert.deepEqual(await rpc(db, 'a', 'photo_quota_use'), { allowed: false, used: 3, limit: 3, pro: false });
  assert.deepEqual(await rpc(db, 'a', 'photo_quota'), { allowed: false, used: 3, limit: 3, pro: false });
  makePro(db, 'b', '2026-10-25T11:59:59.000Z');
  assert.equal((await rpc(db, 'b', 'photo_quota')).limit, 3);
  db.raw.prepare("UPDATE pro_status SET until = '2027-01-01T00:00:00.000Z' WHERE user_id = 'b'").run();
  const r = await Promise.all(Array.from({ length: 55 }, () => rpc(db, 'b', 'photo_quota_use')));
  assert.equal(r.filter((x) => x.allowed).length, 50);
  assert.equal((await rpc(db, 'a', 'photo_quota')).used, 3);
});

test('zonder sessie kan geen enkele teller- of Supporter-functie', async () => {
  const db = setup();
  for (const name of ['ai_quota', 'ai_quota_use', 'photo_quota', 'photo_quota_use', 'ai_report', 'my_pro', 'pro_show_badge', 'pro_set_frame', 'my_features', 'roadmap_list', 'roadmap_vote', 'notify_register', 'notify_unregister']) {
    await fails(rpc(db, null, name, {}), 'PGRST301');
  }
});

// ---- AI-meldingen ----

test('ai_report: soort, lege tekst, inkorten en 20 per 24 uur', async () => {
  const db = setup();
  assert.equal(await rpc(db, 'a', 'ai_report', { p_kind: 'nope', p_text: 'x', p_note: null }), 'bad_kind');
  assert.equal(await rpc(db, 'a', 'ai_report', { p_kind: null, p_text: 'x', p_note: null }), 'bad_kind');
  assert.equal(await rpc(db, 'a', 'ai_report', { p_kind: 'coach', p_text: '   ', p_note: null }), 'empty');
  assert.equal(await rpc(db, 'a', 'ai_report', { p_kind: 'coach', p_text: `  ${'é'.repeat(5000)} `, p_note: '  ' }), 'reported');
  const row = db.raw.prepare('SELECT * FROM ai_reports').get();
  assert.equal(row.reporter, 'a');
  assert.equal([...row.text].length, 4000);
  assert.equal(row.note, null);
  for (let i = 0; i < 19; i++) assert.equal(await rpc(db, 'a', 'ai_report', { p_kind: 'photo', p_text: `t${i}`, p_note: 'n' }), 'reported');
  assert.equal(await rpc(db, 'a', 'ai_report', { p_kind: 'photo', p_text: 'te veel', p_note: null }), 'limit');
  // Een ander heeft zijn eigen grens; na 24 uur mag het weer
  assert.equal(await rpc(db, 'b', 'ai_report', { p_kind: 'label', p_text: 'x', p_note: null }), 'reported');
  assert.equal(await rpc(db, 'a', 'ai_report', { p_kind: 'photo', p_text: 'later', p_note: null }, at('2026-10-26T12:00:00.001Z')), 'reported');
});

test('ai_report: meldingen tegelijk gaan niet over de 20', async () => {
  const db = setup();
  const r = await Promise.all(Array.from({ length: 30 }, (_, i) => rpc(db, 'a', 'ai_report', { p_kind: 'voice', p_text: `t${i}`, p_note: null })));
  assert.equal(r.filter((x) => x === 'reported').length, 20);
  assert.equal(r.filter((x) => x === 'limit').length, 10);
});

// ---- Supporter ----

test('my_pro: standaard zonder rij, anders je eigen status (ook verlopen)', async () => {
  const db = setup();
  assert.deepEqual(await rpc(db, 'a', 'my_pro'), { pro: false, until: null, source: null, show_badge: true, frame: null });
  makePro(db, 'a', '2026-12-01T00:00:00.000Z', { source: 'play', frame: 'glow', show_badge: 0 });
  assert.deepEqual(await rpc(db, 'a', 'my_pro'), { pro: true, until: '2026-12-01T00:00:00.000Z', source: 'play', show_badge: false, frame: 'glow' });
  assert.equal((await rpc(db, 'a', 'my_pro', {}, at('2026-12-01T00:00:00.000Z'))).pro, false);
  // b ziet de status van a niet
  assert.equal((await rpc(db, 'b', 'my_pro')).pro, false);
});

test('pro_show_badge: alleen je eigen rij, null = tonen', async () => {
  const db = setup();
  makePro(db, 'a');
  makePro(db, 'b');
  assert.equal(await rpc(db, 'a', 'pro_show_badge', { p_show: false }), null);
  assert.equal((await rpc(db, 'a', 'my_pro')).show_badge, false);
  assert.equal((await rpc(db, 'b', 'my_pro')).show_badge, true);
  await rpc(db, 'a', 'pro_show_badge', { p_show: null });
  assert.equal((await rpc(db, 'a', 'my_pro')).show_badge, true);
  await fails(rpc(db, 'a', 'pro_show_badge', { p_show: 'misschien' }), '22P02');
});

test('pro_set_frame: alleen met een lopend abonnement, alleen bekende randen', async () => {
  const db = setup();
  assert.equal(await rpc(db, 'a', 'pro_set_frame', { p_frame: 'glow' }), false);
  makePro(db, 'a');
  makePro(db, 'b', '2026-01-01T00:00:00.000Z');
  assert.equal(await rpc(db, 'a', 'pro_set_frame', { p_frame: 'royal' }), true);
  assert.equal((await rpc(db, 'a', 'my_pro')).frame, 'royal');
  assert.equal(await rpc(db, 'b', 'pro_set_frame', { p_frame: 'glow' }), false);
  assert.equal((await rpc(db, 'b', 'my_pro')).frame, null);
  await fails(rpc(db, 'a', 'pro_set_frame', { p_frame: 'goud' }), 'P0001', 'onbekende rand');
  assert.equal(await rpc(db, 'a', 'pro_set_frame', { p_frame: null }), true);
  assert.equal((await rpc(db, 'a', 'my_pro')).frame, null);
});

// ---- Features ----

test('my_features: vroeg open voor Supporters, daarna voor iedereen', async () => {
  const db = setup();
  makePro(db, 'b');
  const ins = db.raw.prepare('INSERT INTO features (id, title_en, title_nl, early_from, public_from) VALUES (?, ?, ?, ?, ?)');
  ins.run('zeta', 'Zeta', 'Zeta', '2026-10-20T00:00:00.000Z', '2026-11-01T00:00:00.000Z');
  ins.run('alpha', 'Alpha', 'Alfa', null, null);
  ins.run('open', 'Open', 'Open', null, '2026-10-01T00:00:00.000Z');
  const a = await rpc(db, 'a', 'my_features');
  assert.deepEqual(a.map((f) => f.id), ['alpha', 'open', 'zeta']);
  assert.deepEqual(a[2], {
    id: 'zeta', title_en: 'Zeta', title_nl: 'Zeta', early_from: '2026-10-20T00:00:00.000Z', public_from: '2026-11-01T00:00:00.000Z', enabled: false, early: true,
  });
  assert.deepEqual(a.map((f) => [f.enabled, f.early]), [[false, false], [true, false], [false, true]]);
  assert.deepEqual((await rpc(db, 'b', 'my_features')).map((f) => [f.enabled, f.early]), [[false, false], [true, false], [true, true]]);
  // Voor het vroege venster: nog niemand; na public_from: iedereen, niet meer "vroeg"
  assert.deepEqual((await rpc(db, 'b', 'my_features', {}, at('2026-10-19T00:00:00.000Z')))[2].enabled, false);
  assert.deepEqual((await rpc(db, 'a', 'my_features', {}, at('2026-11-01T00:00:00.000Z'))).map((f) => [f.enabled, f.early])[2], [true, false]);
});

// ---- Roadmap ----

const ITEM = (n) => `00000000-0000-4000-8000-00000000000${n}`;
function roadmap(db) {
  const ins = db.raw.prepare('INSERT INTO roadmap_items (id, title_en, title_nl, status, sort, created_at) VALUES (?, ?, ?, ?, ?, ?)');
  ins.run(ITEM(1), 'Idee', 'Idee', 'idea', 1, '2026-01-01T00:00:00.000Z');
  ins.run(ITEM(2), 'Bouw', 'Bouw', 'building', 5, '2026-01-01T00:00:00.000Z');
  ins.run(ITEM(3), 'Plan', 'Plan', 'planned', 1, '2026-01-01T00:00:00.000Z');
  ins.run(ITEM(4), 'Klaar', 'Klaar', 'done', 1, '2026-01-01T00:00:00.000Z');
  ins.run(ITEM(5), 'Idee 2', 'Idee 2', 'idea', 1, '2026-01-02T00:00:00.000Z');
  ins.run(ITEM(6), 'Vroeg', 'Vroeg', 'early', 1, '2026-01-01T00:00:00.000Z');
  ins.run(ITEM(7), 'Idee 3', 'Idee 3', 'idea', 2, '2026-01-01T00:00:00.000Z');
}

test('roadmap_vote: aan en uit, alleen Supporters, open items, hoogstens 3', async () => {
  const db = setup();
  roadmap(db);
  makePro(db, 'a');
  assert.equal(await rpc(db, 'b', 'roadmap_vote', { p_item: ITEM(1), p_on: true }), 'not_pro');
  assert.equal(await rpc(db, 'a', 'roadmap_vote', { p_item: '00000000-0000-4000-8000-000000000099', p_on: true }), 'not_found');
  assert.equal(await rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(4), p_on: true }), 'closed');
  assert.equal(await rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(6), p_on: false }), 'closed');
  await fails(rpc(db, 'a', 'roadmap_vote', { p_item: 'geen-uuid', p_on: true }), '22P02');
  for (const n of [1, 2, 3]) assert.equal(await rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(n), p_on: true }), 'ok');
  assert.equal(await rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(1), p_on: true }), 'ok'); // al gestemd
  assert.equal(await rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(5), p_on: true }), 'limit');
  assert.equal(await rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(1), p_on: false }), 'ok');
  assert.equal(await rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(5), p_on: true }), 'ok');
  // Een stem op een item dat klaar is, telt niet meer mee
  db.raw.prepare("UPDATE roadmap_items SET status = 'done' WHERE id = ?").run(ITEM(5));
  assert.equal(await rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(7), p_on: true }), 'ok');
});

test('roadmap_vote: stemmen tegelijk gaan niet over de 3', async () => {
  const db = setup();
  roadmap(db);
  makePro(db, 'a');
  const r = await Promise.all([1, 2, 3, 5, 7].map((n) => rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(n), p_on: true })));
  assert.equal(r.filter((x) => x === 'ok').length, 3);
  assert.equal(db.raw.prepare("SELECT count(*) AS n FROM roadmap_votes WHERE user_id = 'a'").get().n, 3);
});

test('roadmap_list: volgorde op status, alleen stemmen van Supporters tellen, mine per gebruiker', async () => {
  const db = setup();
  addUser(db, 'c');
  roadmap(db);
  makePro(db, 'a');
  makePro(db, 'b');
  await rpc(db, 'a', 'roadmap_vote', { p_item: ITEM(1), p_on: true });
  await rpc(db, 'b', 'roadmap_vote', { p_item: ITEM(1), p_on: true });
  // Het abonnement van b loopt af: zijn stem blijft staan maar telt niet meer
  db.raw.prepare("UPDATE pro_status SET until = '2026-10-01T00:00:00.000Z' WHERE user_id = 'b'").run();
  const list = await rpc(db, 'c', 'roadmap_list');
  assert.deepEqual(list.map((i) => i.id), [ITEM(2), ITEM(3), ITEM(1), ITEM(5), ITEM(7), ITEM(6), ITEM(4)]);
  assert.deepEqual(list[2], { id: ITEM(1), title_en: 'Idee', title_nl: 'Idee', desc_en: '', desc_nl: '', status: 'idea', sort: 1, votes: 1, mine: false });
  assert.equal((await rpc(db, 'a', 'roadmap_list'))[2].mine, true);
  assert.equal((await rpc(db, 'b', 'roadmap_list'))[2].mine, true);
  // c kan de stem van a niet intrekken
  makePro(db, 'c');
  assert.equal(await rpc(db, 'c', 'roadmap_vote', { p_item: ITEM(1), p_on: false }), 'ok');
  assert.equal((await rpc(db, 'c', 'roadmap_list'))[2].votes, 1);
  assert.equal((await rpc(db, 'a', 'roadmap_list'))[2].mine, true);
});

// ---- Meldingstokens en open uitdagingen ----

test('notify_register: een nieuw token per toestel, hoogstens 5 per gebruiker', async () => {
  const db = setup();
  const tokens = [];
  for (let i = 0; i < 7; i++) tokens.push(await rpc(db, 'a', 'notify_register', {}, at(`2026-10-25T12:00:0${i}.000Z`)));
  assert.ok(tokens.every((t) => /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(t)));
  assert.equal(new Set(tokens).size, 7);
  const kept = db.raw.prepare("SELECT token FROM notify_tokens WHERE user_id = 'a' ORDER BY created_at").all().map((r) => r.token);
  assert.deepEqual(kept, tokens.slice(2));
  // Op hetzelfde moment: de laatst toegevoegde blijven
  const same = [];
  for (let i = 0; i < 6; i++) same.push(await rpc(db, 'b', 'notify_register'));
  assert.deepEqual(db.raw.prepare("SELECT token FROM notify_tokens WHERE user_id = 'b'").all().map((r) => r.token).sort(), same.slice(1).sort());
  assert.equal(db.raw.prepare("SELECT count(*) AS n FROM notify_tokens WHERE user_id = 'a'").get().n, 5);
});

test('notify_unregister: alleen je eigen token', async () => {
  const db = setup();
  const ta = await rpc(db, 'a', 'notify_register');
  assert.equal(await rpc(db, 'b', 'notify_unregister', { p_token: ta }), null);
  assert.equal(db.raw.prepare('SELECT count(*) AS n FROM notify_tokens').get().n, 1);
  assert.equal(await rpc(db, 'a', 'notify_unregister', { p_token: ta.toUpperCase() }), null);
  assert.equal(db.raw.prepare('SELECT count(*) AS n FROM notify_tokens').get().n, 0);
  await fails(rpc(db, 'a', 'notify_unregister', { p_token: 'x' }), '22P02');
});

test('pending_challenges: zonder sessie, alleen open uitdagingen van de laatste week voor de eigenaar van het token', async () => {
  const db = setup();
  addUser(db, 'c');
  db.raw.prepare("INSERT INTO friend_profiles (user_id, code, name) VALUES ('b', 'BBBB', 'Bea')").run();
  const battle = db.raw.prepare('INSERT INTO battles (id, week, challenger, opponent, accepted, created_at) VALUES (?, ?, ?, ?, ?, ?)');
  battle.run('b1', '2026-10-19', 'b', 'a', 0, '2026-10-20T10:00:00.000Z');
  battle.run('b2', '2026-10-19', 'c', 'a', 0, '2026-10-21T10:00:00.000Z'); // c heeft geen profiel
  battle.run('b3', '2026-10-12', 'a', 'c', 0, '2026-10-13T10:00:00.000Z'); // a daagt uit: niet voor a
  battle.run('b4', '2026-10-12', 'b', 'c', 1, '2026-10-13T10:00:00.000Z');
  battle.run('b5', '2026-10-05', 'b', 'a', 0, '2026-10-06T10:00:00.000Z'); // te oud
  battle.run('b6', '2026-10-26', 'c', 'b', 0, '2026-10-24T10:00:00.000Z'); // voor b
  const ta = await rpc(db, 'a', 'notify_register');
  assert.deepEqual(await rpc(db, null, 'pending_challenges', { p_token: ta }), [{ id: 'b2', name: '' }, { id: 'b1', name: 'Bea' }]);
  // De grens is vandaag (UTC) min 7 dagen: week 19-10 telt tot en met 26-10
  assert.deepEqual(await rpc(db, null, 'pending_challenges', { p_token: ta }, at('2026-10-27T00:00:00.000Z')), []);
  // Een onbekend, ingetrokken of ontbrekend token geeft niets prijs; geen uuid is een fout zoals in Postgres
  assert.deepEqual(await rpc(db, null, 'pending_challenges', { p_token: '00000000-0000-4000-8000-000000000000' }), []);
  assert.deepEqual(await rpc(db, null, 'pending_challenges', {}), []);
  await fails(rpc(db, null, 'pending_challenges', { p_token: "' OR 1=1 --" }), '22P02');
  await rpc(db, 'a', 'notify_unregister', { p_token: ta });
  assert.deepEqual(await rpc(db, null, 'pending_challenges', { p_token: ta }), []);
  // Hoogstens 10, nieuwste eerst
  const tc = await rpc(db, 'c', 'notify_register');
  for (let i = 0; i < 12; i++) {
    addUser(db, `x${i}`);
    battle.run(`x${i}`, '2026-10-19', `x${i}`, 'c', 0, `2026-10-20T10:00:${String(i).padStart(2, '0')}.000Z`);
  }
  const rows = await rpc(db, null, 'pending_challenges', { p_token: tc });
  assert.equal(rows.length, 10);
  assert.equal(rows[0].id, 'x11');
});
