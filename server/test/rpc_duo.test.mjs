// Duo (src/rpc/duo.js): de koper van een Duo-abonnement kiest één vriend die ook Supporter is zolang het loopt.
import './workers-stub.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addUser, d1 } from './d1.mjs';

const { callRpc } = await import('../src/rpc/index.js');
const { Internal } = await import('../src/internal.js');
const { syncAllDuos } = await import('../src/rpc/duo.js');

const [A, B, C, D] = ['aaaaaaaa-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000003', 'dddddddd-0000-4000-8000-000000000004'];
const NOW = new Date('2026-11-01T12:00:00.000Z');
const LATER = (days) => new Date(NOW.getTime() + days * 86_400_000);
const YEAR = '2027-11-01T12:00:00.000Z';

function setup() {
  const db = d1();
  for (const id of [A, B, C, D]) addUser(db, id);
  // A is bevriend met B, C en D; C en D onderling ook
  for (const [x, y] of [[A, B], [A, C], [A, D], [C, D]]) db.raw.prepare('INSERT INTO friendships (requester, addressee, accepted) VALUES (?, ?, 1)').run(x, y);
  const rpc = (uid, fn, p = {}, now = NOW) => callRpc(fn, p, { db, env: {}, uid, now });
  const pro = (uid, now = NOW) => rpc(uid, 'my_pro', {}, now);
  return { db, rpc, pro };
}
const buyDuo = (db, owner, expiry = YEAR, token = `duo-token-${owner}`) => {
  db.raw.prepare('INSERT OR REPLACE INTO play_purchases (purchase_token, user_id, product, expiry, updated_at) VALUES (?, ?, ?, ?, ?)').run(token, owner, 'duo_yearly', expiry, NOW.toISOString());
  db.raw.prepare("INSERT OR REPLACE INTO pro_status (user_id, until, source) VALUES (?, ?, 'play')").run(owner, expiry);
};

test('zonder Duo-abonnement: geen partner kiezen', async () => {
  const { rpc } = setup();
  assert.deepEqual(await rpc(A, 'duo_status'), { role: null, active: false, until: null });
  assert.equal((await rpc(A, 'duo_set_partner', { p_other: B })).result, 'no_duo');
});

test('partner kiezen: alleen een vriend, niet jezelf; de partner is Supporter tot de vervaldatum', async () => {
  const { db, rpc, pro } = setup();
  buyDuo(db, A);
  assert.equal((await rpc(A, 'duo_set_partner', { p_other: A })).result, 'self');
  assert.equal((await rpc(B, 'duo_set_partner', { p_other: C })).result, 'no_duo');
  db.raw.prepare('DELETE FROM friendships WHERE requester = ? AND addressee = ?').run(A, D);
  assert.equal((await rpc(A, 'duo_set_partner', { p_other: D })).result, 'not_friends');
  const r = await rpc(A, 'duo_set_partner', { p_other: B });
  assert.equal(r.result, 'ok');
  assert.equal(r.status.role, 'owner');
  assert.equal(r.status.partner.id, B);
  const p = await pro(B);
  assert.equal(p.pro, true);
  assert.equal(p.source, 'duo');
  assert.equal(p.until, YEAR);
  const s = await rpc(B, 'duo_status');
  assert.deepEqual({ role: s.role, active: s.active, owner: s.owner.id }, { role: 'partner', active: true, owner: A });
  await assert.rejects(rpc(A, 'duo_set_partner', { p_other: 'geen-uuid' }), { code: '22P02' });
});

test('wisselen kan pas na 30 dagen (ook weghalen telt); de vorige partner stopt meteen', async () => {
  const { db, rpc, pro } = setup();
  buyDuo(db, A);
  await rpc(A, 'duo_set_partner', { p_other: B });
  assert.equal((await rpc(A, 'duo_set_partner', { p_other: C })).result, 'too_soon');
  assert.equal((await rpc(A, 'duo_set_partner', { p_other: B })).result, 'ok', 'dezelfde opnieuw is geen wissel');
  const later = LATER(31);
  assert.equal((await rpc(A, 'duo_set_partner', { p_other: C }, later)).result, 'ok');
  assert.equal((await pro(B, later)).pro, false);
  assert.equal((await pro(C, later)).source, 'duo');
  // Weghalen en meteen iemand anders: te snel
  await rpc(A, 'duo_remove', {}, later);
  assert.equal((await pro(C, later)).pro, false);
  const s = await rpc(A, 'duo_set_partner', { p_other: D }, LATER(32));
  assert.equal(s.result, 'too_soon');
  assert.ok(s.status.next_change > LATER(32).toISOString());
});

test('iemand kan maar in één Duo zitten', async () => {
  const { db, rpc } = setup();
  buyDuo(db, A);
  buyDuo(db, C);
  await rpc(A, 'duo_set_partner', { p_other: B });
  db.raw.prepare('INSERT INTO friendships (requester, addressee, accepted) VALUES (?, ?, 1)').run(C, B);
  assert.equal((await rpc(C, 'duo_set_partner', { p_other: B })).result, 'taken');
  // Ook een koper met een partner kan zelf geen partner zijn
  await rpc(C, 'duo_set_partner', { p_other: D });
  assert.equal((await rpc(A, 'duo_set_partner', { p_other: C }, LATER(31))).result, 'taken');
});

test('een eigen, langere Supporter van de partner blijft; na de Duo komt die terug', async () => {
  const { db, rpc, pro } = setup();
  buyDuo(db, A, '2026-12-01T00:00:00.000Z');
  db.raw.prepare("INSERT INTO pro_status (user_id, until, source) VALUES (?, '2028-01-01T00:00:00.000Z', 'manual')").run(B);
  await rpc(A, 'duo_set_partner', { p_other: B });
  assert.deepEqual({ ...(await pro(B)) }, { ...(await pro(B)), source: 'manual', until: '2028-01-01T00:00:00.000Z' });
  // Kortere eigen Supporter: Duo gaat voor, de eigen komt terug na het stoppen
  db.raw.prepare("UPDATE pro_status SET until = '2026-11-15T00:00:00.000Z' WHERE user_id = ?").run(B);
  await rpc(A, 'duo_remove', {});
  db.raw.prepare('UPDATE duo_members SET changed_at = ? WHERE owner = ?').run(LATER(-40).toISOString(), A);
  await rpc(A, 'duo_set_partner', { p_other: B });
  assert.equal((await pro(B)).source, 'duo');
  await rpc(B, 'duo_leave', {});
  const back = await pro(B);
  assert.deepEqual([back.source, back.until], ['manual', '2026-11-15T00:00:00.000Z']);
});

test('Google Play: verlengen en stoppen van het abonnement nemen de partner mee', async () => {
  const { db, rpc, pro } = setup();
  const internal = new Internal({ waitUntil() {} }, { DB: db, BETTER_AUTH_SECRET: 'x'.repeat(40) });
  buyDuo(db, A, '2026-12-01T00:00:00.000Z');
  await rpc(A, 'duo_set_partner', { p_other: B });
  // Verlengd: Google meldt een nieuwe vervaldatum
  db.raw.prepare("UPDATE play_purchases SET expiry = '2027-01-01T00:00:00.000Z' WHERE user_id = ?").run(A);
  await internal.grantPro(A, '2027-01-01T00:00:00.000Z');
  assert.equal((await pro(B)).until, '2027-01-01T00:00:00.000Z');
  // Opgezegd en afgelopen: de aankoop krijgt de vervaldatum "nu", dan revokePro
  db.raw.prepare('UPDATE play_purchases SET expiry = ? WHERE user_id = ?').run(NOW.toISOString(), A);
  await internal.revokePro(A, `duo-token-${A}`, NOW.getTime());
  assert.equal((await pro(B, LATER(1))).pro, false);
  assert.equal((await rpc(A, 'duo_status', {}, LATER(1))).active, false);
});

test('elke nacht: een afgelopen Duo stopt ook bij de partner zonder melding van Google', async () => {
  const { db, rpc, pro } = setup();
  buyDuo(db, A, '2026-11-10T00:00:00.000Z');
  await rpc(A, 'duo_set_partner', { p_other: B });
  assert.equal(await syncAllDuos(db, LATER(5)), 1);
  assert.equal((await pro(B, LATER(5))).pro, true);
  // De vervaldatum is voorbij: niets meer verlengen (pro_status loopt af op dezelfde datum)
  await syncAllDuos(db, LATER(20));
  assert.equal((await pro(B, LATER(20))).pro, false);
});

test('account van de koper verwijderd: de Duo-rij is weg, de partner houdt wat al betaald was', async () => {
  const { db, rpc, pro } = setup();
  buyDuo(db, A);
  await rpc(A, 'duo_set_partner', { p_other: B });
  await rpc(A, 'delete_account');
  assert.equal(db.raw.prepare('SELECT count(*) n FROM duo_members').get().n, 0);
  assert.equal((await pro(B)).pro, true);
});

test('een andere gebruiker kan niets aan andermans Duo veranderen', async () => {
  const { db, rpc, pro } = setup();
  buyDuo(db, A);
  await rpc(A, 'duo_set_partner', { p_other: B });
  // C heeft geen Duo: kan B niet weghalen of wisselen
  await rpc(C, 'duo_remove', {});
  assert.equal((await pro(B)).source, 'duo');
  assert.equal((await rpc(C, 'duo_set_partner', { p_other: D })).result, 'no_duo');
  assert.equal((await rpc(C, 'duo_status')).role, null);
});
