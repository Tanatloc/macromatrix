// Tickets voor de live WebSocket (src/live.js): ondertekend, 60 s geldig, en alleen zolang de sessie bestaat.
import './workers-stub.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addUser, d1 } from './d1.mjs';

const { checkTicket, makeTicket } = await import('../src/live.js');

function setup() {
  const db = d1();
  addUser(db, 'u1');
  const now = new Date().toISOString();
  db.raw
    .prepare('INSERT INTO session (id, "expiresAt", token, "createdAt", "updatedAt", "userId") VALUES (?, ?, ?, ?, ?, ?)')
    .run('s1', new Date(Date.now() + 86_400_000).toISOString(), 'tok', now, now, 'u1');
  return { DB: db, BETTER_AUTH_SECRET: 'x'.repeat(40) };
}

test('een geldig ticket geeft gebruiker en sessie', async () => {
  const env = setup();
  assert.deepEqual(await checkTicket(env, await makeTicket(env, 'u1', 's1')), { uid: 'u1', sid: 's1' });
});

test('vervalt na 60 s, en een gewijzigd ticket of ander geheim telt niet', async () => {
  const env = setup();
  const t = await makeTicket(env, 'u1', 's1');
  assert.equal(await checkTicket(env, t, Date.now() + 61_000), null);
  assert.equal(await checkTicket(env, t.replace('u1.', 'u2.')), null);
  assert.equal(await checkTicket({ ...env, BETTER_AUTH_SECRET: 'y'.repeat(40) }, t), null);
  assert.equal(await checkTicket(env, 'onzin'), null);
});

test('uitgelogde sessie: het ticket werkt niet meer', async () => {
  const env = setup();
  const t = await makeTicket(env, 'u1', 's1');
  env.DB.raw.exec("DELETE FROM session WHERE id = 's1'");
  assert.equal(await checkTicket(env, t), null);
});

test('zonder (lang genoeg) geheim geen tickets', async () => {
  const env = setup();
  await assert.rejects(makeTicket({ ...env, BETTER_AUTH_SECRET: undefined }, 'u1', 's1'));
  await assert.rejects(makeTicket({ ...env, BETTER_AUTH_SECRET: 'kort' }, 'u1', 's1'));
});
