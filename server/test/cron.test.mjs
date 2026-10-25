// Nachtelijk opruimen (src/cron.js).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { d1 } from './d1.mjs';
import { cleanup } from '../src/cron.js';

test('niet-bevestigde accounts na 30 dagen weg, bevestigde en recente blijven; verlopen sessies en codes weg', async () => {
  const db = d1();
  const now = new Date('2026-11-30T03:00:00Z');
  const ago = (d) => new Date(now.getTime() - d * 86_400_000).toISOString();
  const user = (id, verified, created) =>
    db.raw.prepare('INSERT INTO "user" (id, name, email, "emailVerified", "createdAt", "updatedAt") VALUES (?, ?, ?, ?, ?, ?)').run(id, '', `${id}@x.org`, verified, created, created);
  user('oud-onbevestigd', 0, ago(31));
  user('nieuw-onbevestigd', 0, ago(5));
  user('oud-bevestigd', 1, ago(400));
  const sess = (id, exp) => db.raw.prepare('INSERT INTO session (id, "expiresAt", token, "createdAt", "updatedAt", "userId") VALUES (?, ?, ?, ?, ?, ?)').run(id, exp, id, ago(1), ago(1), 'oud-bevestigd');
  sess('verlopen', ago(1));
  sess('geldig', ago(-10));
  db.raw.prepare("INSERT INTO verification (id, identifier, value, \"expiresAt\", \"createdAt\", \"updatedAt\") VALUES ('v', 'x', 'y', ?, ?, ?)").run(ago(1), ago(2), ago(2));
  db.raw.prepare('INSERT INTO signup_ips (ip_hash, at) VALUES (?, ?), (?, ?)').run('a', ago(2), 'b', ago(0.1));
  const r = await cleanup(db, now);
  assert.deepEqual(r, { users: 1, sessions: 1, codes: 1, limits: 0, ips: 1, outbox: 0 });
  assert.deepEqual(db.raw.prepare('SELECT id FROM "user" ORDER BY id').all().map((x) => x.id), ['nieuw-onbevestigd', 'oud-bevestigd']);
  assert.deepEqual(db.raw.prepare('SELECT id FROM session').all().map((x) => x.id), ['geldig']);
});
