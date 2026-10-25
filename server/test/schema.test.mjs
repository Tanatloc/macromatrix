// D1-schema (migrations/*.sql) in SQLite: de synctriggers doen wat sync_stamp en limit_rows in Supabase deden, en
// de omgezette CHECK-regels en sleutels houden stand. Draait met node:sqlite; tool/d1_check.mjs doet dezelfde
// kernproeven op een echte D1.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

const dir = new URL('../migrations/', import.meta.url);

function freshDb() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON'); // D1 heeft dit altijd aan
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) db.exec(readFileSync(new URL(f, dir), 'utf8'));
  const now = new Date().toISOString();
  for (const id of ['u1', 'u2']) {
    db.prepare('INSERT INTO "user" (id, name, email, emailVerified, createdAt, updatedAt) VALUES (?,?,?,?,?,?)').run(id, '', `${id}@example.com`, 1, now, now);
  }
  return db;
}

// Zoals de Worker het zal doen: één upsert per rij, server_seq nooit meegegeven
function push(db, row) {
  const r = { user_id: 'u1', day: '2026-10-25', meal: 1, food_ref: 'ciqual:1', name: 'Banaan', grams: 100, quantity: 100, nutrients: '{}', created_at: 1, deleted: 0, ...row };
  const cols = Object.keys(r);
  db.prepare(
    `INSERT INTO diary (${cols.join(',')}) VALUES (${cols.map(() => '?').join(',')})
     ON CONFLICT (user_id, id) DO UPDATE SET ${cols.filter((c) => c !== 'user_id' && c !== 'id').map((c) => `${c} = excluded.${c}`).join(', ')}`,
  ).run(...cols.map((c) => r[c]));
}
const get = (db, id) => db.prepare('SELECT * FROM diary WHERE user_id = ? AND id = ?').get('u1', id);

test('nieuwe en gewijzigde rijen krijgen een oplopend server_seq', () => {
  const db = freshDb();
  push(db, { id: 'a', updated_at: 1000 });
  push(db, { id: 'b', updated_at: 1000 });
  const a1 = get(db, 'a').server_seq, b1 = get(db, 'b').server_seq;
  assert.ok(a1 > 0 && b1 > a1);
  push(db, { id: 'a', updated_at: 2000, grams: 50 });
  const a2 = get(db, 'a');
  assert.ok(a2.server_seq > b1);
  assert.equal(a2.grams, 50);
  assert.equal(db.prepare('SELECT seq FROM sync_seq').get().seq, a2.server_seq);
});

test('een oudere versie wordt stil genegeerd; dezelfde tijd telt wel', () => {
  const db = freshDb();
  push(db, { id: 'a', updated_at: 2000, grams: 100 });
  const before = get(db, 'a');
  push(db, { id: 'a', updated_at: 1500, grams: 1 });
  assert.deepEqual(get(db, 'a'), before);
  push(db, { id: 'a', updated_at: 2000, grams: 7 });
  assert.equal(get(db, 'a').grams, 7);
});

test('een klok die voorloopt: hoogstens nu + 5 minuten, ook bij het vergelijken', () => {
  const db = freshDb();
  const now = Date.now();
  push(db, { id: 'a', updated_at: now + 3_600_000 });
  const at = get(db, 'a').updated_at;
  assert.ok(at <= Date.now() + 300_000 && at >= now + 299_000, `${at - now}`);
  // Een gewone wijziging vlak daarna (eigen klok juist) mag niet "ouder" lijken dan het toekomstige tijdstip van 1 uur
  push(db, { id: 'a', updated_at: now + 300_000 + 1000, grams: 3 });
  assert.equal(get(db, 'a').grams, 3);
});

test('user_id van een rij kan niet wijzigen', () => {
  const db = freshDb();
  push(db, { id: 'a', updated_at: 1 });
  assert.throws(() => db.exec("UPDATE diary SET user_id = 'u2' WHERE id = 'a'"), /user_id/);
});

test('limiet per gebruiker: 50.000 actieve rijen; een bestaande rij bijwerken blijft kunnen', () => {
  const db = freshDb();
  db.exec('UPDATE import_mode SET active = 1');
  const ins = db.prepare("INSERT INTO diary (user_id, id, day, meal, food_ref, name, grams, quantity, nutrients, created_at, updated_at) VALUES ('u1', ?, 'd', 1, 'r', 'n', 1, 1, '{}', 1, 1)");
  db.exec('BEGIN');
  for (let i = 0; i < 50_000; i++) ins.run(`r${i}`);
  db.exec('COMMIT');
  db.exec('UPDATE import_mode SET active = 0');
  assert.throws(() => push(db, { id: 'nieuw', updated_at: 2 }), /te veel rijen in diary/);
  push(db, { id: 'r5', updated_at: 2, grams: 9 });
  assert.equal(get(db, 'r5').grams, 9);
  // Een andere gebruiker heeft zijn eigen limiet
  push(db, { id: 'x', user_id: 'u2', updated_at: 2 });
});

test('rijtellers (0004): blijven gelijk aan het echte aantal bij nieuw, bijwerken, wissen, terugzetten en verwijderen', () => {
  const db = freshDb();
  const counts = (u = 'u1') => db.prepare("SELECT total, live FROM row_counts WHERE user_id = ? AND tbl = 'diary'").get(u);
  const real = (u = 'u1') => db.prepare('SELECT count(*) AS total, coalesce(sum(deleted = 0), 0) AS live FROM diary WHERE user_id = ?').get(u);
  const same = () => assert.deepEqual({ ...counts() }, { ...real() });
  for (let i = 0; i < 5; i++) push(db, { id: `r${i}`, updated_at: 1 });
  same();
  push(db, { id: 'r1', updated_at: 2, grams: 5 }); // bijwerken telt niet
  push(db, { id: 'r2', updated_at: 3, deleted: 1 }); // gewist (blijft als rij voor de sync)
  push(db, { id: 'r9', updated_at: 3, deleted: 1 }); // meteen gewist binnengekomen
  same();
  assert.deepEqual({ ...counts() }, { total: 6, live: 4 });
  push(db, { id: 'r2', updated_at: 4, deleted: 0 }); // teruggezet
  db.exec("DELETE FROM diary WHERE user_id = 'u1' AND id IN ('r3', 'r9')");
  same();
  // Ook in importmodus (import en herstel van een back-up)
  db.exec('UPDATE import_mode SET active = 1');
  push(db, { id: 'imp', updated_at: 5, server_seq: 7 });
  db.exec('UPDATE import_mode SET active = 0');
  same();
  db.exec("DELETE FROM \"user\" WHERE id = 'u1'");
  assert.equal(db.prepare("SELECT count(*) AS n FROM row_counts WHERE user_id = 'u1'").get().n, 0);
});

test('rijtellers (0004): de limiet telt geen rijen meer, alleen de teller', () => {
  const db = freshDb();
  db.exec("INSERT INTO row_counts (user_id, tbl, total, live) VALUES ('u1', 'diary', 200000, 10) ON CONFLICT DO UPDATE SET total = 200000, live = 10");
  assert.throws(() => push(db, { id: 'nieuw', updated_at: 2 }), /te veel rijen in diary/);
  db.exec("UPDATE row_counts SET total = 199999 WHERE user_id = 'u1'");
  push(db, { id: 'nieuw', updated_at: 2 });
  const plan = db.prepare("EXPLAIN QUERY PLAN SELECT 1 FROM row_counts WHERE user_id = 'u1' AND tbl = 'diary'").all().map((r) => r.detail).join(' ');
  assert.match(plan, /PRIMARY KEY/);
});

test('importmodus: server_seq en updated_at komen ongewijzigd binnen', () => {
  const db = freshDb();
  db.exec('UPDATE import_mode SET active = 1');
  push(db, { id: 'a', updated_at: 9_999_999_999_999, server_seq: 42 });
  db.exec('UPDATE import_mode SET active = 0');
  const a = get(db, 'a');
  assert.equal(a.server_seq, 42);
  assert.equal(a.updated_at, 9_999_999_999_999);
});

test('alle negen synctabellen hebben de vijf triggers', () => {
  const db = freshDb();
  const names = db.prepare("SELECT name FROM sqlite_master WHERE type = 'trigger'").all().map((r) => r.name);
  for (const t of ['settings', 'foods', 'diary', 'meals', 'biometrics', 'notes', 'exercise', 'fasts', 'repeats']) {
    for (const s of ['older', 'owner', 'limit', 'stamp_insert', 'stamp_update']) assert.ok(names.includes(`${t}_${s}`), `${t}_${s}`);
  }
});

test('settings (sleutel "key") en notes (sleutel day, zonder deleted) werken ook', () => {
  const db = freshDb();
  db.prepare("INSERT INTO settings (user_id, key, value, updated_at) VALUES ('u1', 'ui', '{}', 5) ON CONFLICT (user_id, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at").run();
  db.prepare("INSERT INTO settings (user_id, key, value, updated_at) VALUES ('u1', 'ui', '{\"x\":1}', 4) ON CONFLICT (user_id, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at").run();
  assert.equal(db.prepare("SELECT value FROM settings WHERE key = 'ui'").get().value, '{}');
  db.prepare("INSERT INTO notes (user_id, day, text, updated_at) VALUES ('u1', '2026-10-25', 'hoi', 1)").run();
  assert.ok(db.prepare('SELECT server_seq FROM notes').get().server_seq > 0);
});

test('account verwijderen ruimt alles van die gebruiker op (ON DELETE CASCADE)', () => {
  const db = freshDb();
  push(db, { id: 'a', updated_at: 1 });
  db.prepare("INSERT INTO friendships (requester, addressee) VALUES ('u1', 'u2')").run();
  db.prepare("INSERT INTO weekly_scores (user_id, week, score, days) VALUES ('u1', '2026-10-19', 50, 3)").run();
  db.prepare('DELETE FROM "user" WHERE id = ?').run('u1');
  for (const t of ['diary', 'friendships', 'weekly_scores']) assert.equal(db.prepare(`SELECT count(*) n FROM ${t}`).get().n, 0, t);
});

test('omgezette CHECK-regels', () => {
  const db = freshDb();
  // Week moet een maandag zijn (EXTRACT(isodow) = 1)
  assert.throws(() => db.prepare("INSERT INTO weekly_scores (user_id, week, score, days) VALUES ('u1', '2026-10-20', 50, 3)").run(), /CHECK/);
  // features.id: alleen a-z, 0-9 en _
  db.prepare("INSERT INTO features (id, title_en, title_nl) VALUES ('training_days', 'a', 'b')").run();
  assert.throws(() => db.prepare("INSERT INTO features (id, title_en, title_nl) VALUES ('Fout-id', 'a', 'b')").run(), /CHECK/);
  // = ANY (ARRAY[...]) -> IN (...)
  assert.throws(() => db.prepare("INSERT INTO ai_usage (user_id, kind, day, count) VALUES ('u1', 'iets', '2026-10-25', 1)").run(), /CHECK/);
  db.prepare("INSERT INTO ai_usage (user_id, kind, day, count) VALUES ('u1', 'voice', '2026-10-25', 1)").run();
  // boolean -> 0/1
  assert.throws(() => db.prepare("INSERT INTO friendships (requester, addressee, accepted) VALUES ('u1', 'u2', 2)").run(), /CHECK/);
  // lengtes (char_length -> length telt tekens, niet bytes)
  db.prepare("INSERT INTO friend_profiles (user_id, code, name) VALUES ('u1', 'ABCD1234', ?)").run('é'.repeat(40));
  assert.throws(() => db.prepare("INSERT INTO friend_profiles (user_id, code, name) VALUES ('u2', 'ABCD1235', ?)").run('é'.repeat(41)), /CHECK/);
});

test('één battle per paar per week, in welke richting ook', () => {
  const db = freshDb();
  db.prepare("INSERT INTO battles (id, week, challenger, opponent) VALUES ('b1', '2026-10-19', 'u1', 'u2')").run();
  assert.throws(() => db.prepare("INSERT INTO battles (id, week, challenger, opponent) VALUES ('b2', '2026-10-19', 'u2', 'u1')").run(), /UNIQUE/);
});
