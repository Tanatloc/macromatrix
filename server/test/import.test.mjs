// tool/supabase_to_d1.mjs: Postgres-waarden omzetten, SQL veilig opbouwen en de vergelijking zelf.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { compareRows, importSql, lit, toD1, transform } from '../tool/supabase_to_d1.mjs';

const T = 'timestamp with time zone';

test('waarden: tijd naar ISO in UTC (ms), boolean naar 0/1, getallen blijven exact', () => {
  assert.equal(toD1('2026-10-16T14:03:05.123456+02:00', T), '2026-10-16T12:03:05.123Z');
  assert.equal(toD1(true, 'boolean'), 1);
  assert.equal(toD1(false, 'boolean'), 0);
  assert.equal(toD1(0.1 + 0.2, 'double precision'), 0.30000000000000004);
  assert.equal(toD1(1792936649798, 'bigint'), 1792936649798);
  assert.equal(toD1('2026-10-19', 'date'), '2026-10-19');
  assert.equal(toD1(null, T), null);
  assert.throws(() => toD1('gisteren', T));
  assert.throws(() => toD1('12', 'integer'));
});

test("tekst met ' en ; kan de SQL niet breken", () => {
  assert.equal(lit("a'; DROP TABLE x; --"), "'a''; DROP TABLE x; --'");
  assert.equal(lit(null), 'NULL');
});

// Kleine snapshot zoals export() hem maakt
function snapshot() {
  const col = (name, type) => ({ name, type });
  return {
    users: [{ id: 'u1', email: 'a@example.com', encrypted_password: '$2a$10$abc', email_confirmed_at: '2026-10-16T10:00:00+00:00', created_at: '2026-10-16T09:00:00+00:00', updated_at: null }],
    schema: {
      notes: { key: ['user_id', 'day'], columns: [col('user_id', 'uuid'), col('day', 'text'), col('text', 'text'), col('updated_at', 'bigint'), col('server_ts', T)] },
      settings: { key: ['user_id', 'key'], columns: [col('user_id', 'uuid'), col('key', 'text'), col('value', 'text'), col('updated_at', 'bigint'), col('server_ts', T)] },
      friendships: { key: ['requester', 'addressee'], columns: [col('requester', 'uuid'), col('addressee', 'uuid'), col('accepted', 'boolean'), col('created_at', T)] },
    },
    tables: {
      notes: [{ user_id: 'u1', day: '2026-10-25', text: "o'k", updated_at: 5, server_ts: '2026-10-20T00:00:02+00:00' }],
      settings: [{ user_id: 'u1', key: 'ui', value: '{"a":"' + 'x'.repeat(70000) + '"}', updated_at: 4, server_ts: '2026-10-20T00:00:01+00:00' }],
      friendships: [],
    },
  };
}

test('server_seq volgt de volgorde van server_ts over alle synctabellen heen', () => {
  const { tables, seqCount } = transform(snapshot());
  assert.equal(seqCount, 2);
  assert.equal(tables.settings[0].server_seq, 1);
  assert.equal(tables.notes[0].server_seq, 2);
  assert.ok(!('server_ts' in tables.notes[0]));
});

test('de import-SQL laadt in het echte schema, ook lange tekst, en twee keer laden geeft geen dubbels', () => {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  const dir = new URL('../migrations/', import.meta.url);
  for (const f of readdirSync(dir).sort()) db.exec(readFileSync(new URL(f, dir), 'utf8'));
  const sql = importSql(snapshot());
  // Geen enkele opdracht boven de limiet van D1 (100 KB)
  for (const line of sql.split('\n')) assert.ok(line.length < 100_000, `${line.length}`);
  db.exec(sql);
  db.exec(sql);
  const all = (t) => db.prepare(`SELECT * FROM "${t}"`).all().map((r) => ({ ...r }));
  const d1 = { user: all('user'), account: all('account'), notes: all('notes'), settings: all('settings'), friendships: all('friendships') };
  assert.equal(d1.notes.length, 1);
  assert.equal(d1.settings[0].value.length, 70008);
  assert.equal(d1.notes[0].text, "o'k");
  assert.equal(d1.account[0].password, '$2a$10$abc');
  assert.equal(d1.user[0].emailVerified, 1);
  assert.equal(db.prepare('SELECT active FROM import_mode').get().active, 0);
  // Tweede keer: server_seq ligt 2 hoger (achter wat er al was)
  assert.deepEqual(compareRows(snapshot(), d1, { seqBase: 2 }).diffs, []);
  // De vergelijking vindt een echt verschil
  d1.settings[0].value = '{"x":1}';
  assert.equal(compareRows(snapshot(), d1, { seqBase: 2 }).diffs.length, 1);
});
