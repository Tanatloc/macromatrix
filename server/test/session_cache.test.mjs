// Sessiecache van de Worker (src/index.js): een token werkt meteen nergens meer na uitloggen, overal uitloggen, een
// gewijzigd wachtwoord of een verwijderd account, ook als het nog in het geheugen van een instantie stond.
import './workers-stub.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addUser, d1 } from './d1.mjs';

const { cachedSession } = await import('../src/index.js');

function setup() {
  const db = d1();
  addUser(db, 'u1');
  const now = new Date().toISOString();
  const exp = new Date(Date.now() + 86_400_000).toISOString();
  for (const sid of ['s1', 's2']) {
    db.raw.prepare('INSERT INTO session (id, "expiresAt", token, "createdAt", "updatedAt", "userId") VALUES (?, ?, ?, ?, ?, ?)').run(sid, exp, `tok-${sid}`, now, now, 'u1');
  }
  let loads = 0;
  // Zoals Better Auth: zoekt de sessie op aan de hand van het token
  const load = (auth) => async () => {
    loads++;
    const row = db.raw.prepare('SELECT id, "userId", "expiresAt" FROM session WHERE token = ?').get(auth.replace('Bearer ', ''));
    return row ? { user: { id: row.userId }, session: { id: row.id, expiresAt: row.expiresAt } } : null;
  };
  return { db, load, loads: () => loads };
}

test('tweede keer uit het geheugen (Better Auth niet opnieuw), met één controle in D1', async () => {
  const { db, load, loads } = setup();
  assert.deepEqual(await cachedSession(db, 'Bearer tok-s1', load('Bearer tok-s1')), { uid: 'u1', sid: 's1' });
  assert.deepEqual(await cachedSession(db, 'Bearer tok-s1', load('Bearer tok-s1')), { uid: 'u1', sid: 's1' });
  assert.equal(loads(), 1);
});

test('uitgelogd (de sessierij is weg): meteen geweigerd, ook uit het geheugen', async () => {
  const { db, load } = setup();
  await cachedSession(db, 'Bearer tok-s2', load('Bearer tok-s2'));
  db.raw.prepare("DELETE FROM session WHERE id = 's2'").run();
  assert.equal(await cachedSession(db, 'Bearer tok-s2', load('Bearer tok-s2')), null);
  // En daarna ook niet via Better Auth
  assert.equal(await cachedSession(db, 'Bearer tok-s2', load('Bearer tok-s2')), null);
});

test('account verwijderd (sessies vallen weg met het account): geen toegang meer', async () => {
  const { db, load } = setup();
  await cachedSession(db, 'Bearer tok-s1', load('Bearer tok-s1'));
  db.raw.prepare("DELETE FROM \"user\" WHERE id = 'u1'").run();
  assert.equal(await cachedSession(db, 'Bearer tok-s1', load('Bearer tok-s1')), null);
});

test('verlopen sessie: niet uit het geheugen', async () => {
  const { db, load } = setup();
  await cachedSession(db, 'Bearer tok-s1', load('Bearer tok-s1'));
  db.raw.prepare("UPDATE session SET \"expiresAt\" = '2000-01-01T00:00:00.000Z' WHERE id = 's1'").run();
  assert.equal(await cachedSession(db, 'Bearer tok-s1', async () => null), null);
});
