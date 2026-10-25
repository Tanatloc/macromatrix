// Ingang Internal (src/internal.js): wat de functies van de website met de service-role-sleutel deden.
import './workers-stub.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addUser, d1 } from './d1.mjs';

const { Internal } = await import('../src/internal.js');

function setup() {
  const db = d1();
  addUser(db, 'u1');
  addUser(db, 'u2');
  const api = new Internal({ waitUntil() {} }, { DB: db, BETTER_AUTH_SECRET: 'x'.repeat(40) });
  const pro = (u = 'u1') => db.raw.prepare('SELECT until, source, base_until, base_source FROM pro_status WHERE user_id = ?').get(u);
  return { db, api, pro };
}
const row = (token, user, expiry) => ({ purchase_token: token, user_id: user, product: 'pro_monthly', linked_purchase_token: null, expiry, updated_at: '2026-10-25T00:00:00.000Z' });

test('grantPro: nieuwe rij, verlengen, nooit inkorten', async () => {
  const { api, pro } = setup();
  await api.grantPro('u1', '2026-12-01T00:00:00.000Z');
  assert.deepEqual({ ...pro() }, { until: '2026-12-01T00:00:00.000Z', source: 'play', base_until: null, base_source: null });
  await api.grantPro('u1', '2026-11-01T00:00:00.000Z');
  assert.equal(pro().until, '2026-12-01T00:00:00.000Z');
  await api.grantPro('u1', '2027-01-01T00:00:00.000Z');
  assert.equal(pro().until, '2027-01-01T00:00:00.000Z');
});

test('grantPro over een kortere Supporter met de hand: die wordt onthouden, revokePro zet hem terug', async () => {
  const { db, api, pro } = setup();
  db.raw.prepare("INSERT INTO pro_status (user_id, until, source) VALUES ('u1', '2026-11-15T00:00:00.000Z', 'manual')").run();
  await api.grantPro('u1', '2026-12-01T00:00:00.000Z');
  assert.deepEqual({ ...pro() }, { until: '2026-12-01T00:00:00.000Z', source: 'play', base_until: '2026-11-15T00:00:00.000Z', base_source: 'manual' });
  await api.revokePro('u1', 'tok', Date.parse('2026-11-01T00:00:00.000Z'));
  assert.deepEqual({ ...pro() }, { until: '2026-11-15T00:00:00.000Z', source: 'manual', base_until: null, base_source: null });
});

test('revokePro: tot nu, of tot een ander lopend Play-abonnement; laat Supporter met de hand staan', async () => {
  const { db, api, pro } = setup();
  const now = Date.parse('2026-11-01T00:00:00.000Z');
  await api.grantPro('u1', '2026-12-01T00:00:00.000Z');
  await api.savePurchase(row('token-oud-1', 'u1', '2026-12-01T00:00:00.000Z'));
  await api.savePurchase(row('token-nieuw-1', 'u1', '2026-11-20T00:00:00.000Z'));
  await api.revokePro('u1', 'token-oud-1', now);
  assert.equal(pro().until, '2026-11-20T00:00:00.000Z');
  // Zoals applyPurchase: een beëindigde aankoop wordt eerst bewaard met als vervaldatum "nu"
  await api.savePurchase(row('token-oud-1', 'u1', '2026-11-01T00:00:00.000Z'));
  await api.revokePro('u1', 'token-nieuw-1', Date.parse('2026-11-10T00:00:00.000Z'));
  assert.equal(pro().until, '2026-11-10T00:00:00.000Z');
  db.raw.prepare("INSERT INTO pro_status (user_id, until, source) VALUES ('u2', '2027-01-01T00:00:00.000Z', 'manual')").run();
  await api.revokePro('u2', 'x', now);
  assert.equal(pro('u2').until, '2027-01-01T00:00:00.000Z');
});

test('claimPurchase: wie eerst komt, heeft ze; findPurchase geeft eigenaar, product en vervaldatum', async () => {
  const { api } = setup();
  assert.equal(await api.claimPurchase(row('token-t1-xx', 'u1', '2026-12-01T00:00:00.000Z')), 'u1');
  assert.equal(await api.claimPurchase(row('token-t1-xx', 'u2', '2026-12-01T00:00:00.000Z')), 'u1');
  assert.deepEqual({ ...(await api.findPurchase('token-t1-xx')) }, { user_id: 'u1', product: 'pro_monthly', expiry: '2026-12-01T00:00:00.000Z' });
  assert.equal(await api.findPurchase('onbekend'), null);
});

test('rpc zonder geldige sessie: 401 zoals PostgREST; onbekende functie: 404 PGRST202', async () => {
  const { api } = setup();
  const r = await api.rpc('ai_quota_use', { p_kind: 'label' }, 'Bearer onzin');
  assert.equal(r.status, 401);
  assert.equal(r.body.code, 'PGRST301');
  assert.equal((await api.rpc('bestaat_niet', {}, null)).status, 404);
});
