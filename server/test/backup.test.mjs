// Back-ups (src/backup.js, src/cron.js): versleuteld naar R2, en terugzetten met exact dezelfde inhoud.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addUser, d1 } from './d1.mjs';
import { push } from '../src/sync.js';
import { fingerprint, backupTables, makeBackup, readBackup, restoreBackup, verifyRestore } from '../src/backup.js';
import { dailyBackup, restoreCheck } from '../src/cron.js';

const KEY = Buffer.alloc(32, 7).toString('base64');
const OTHER = Buffer.alloc(32, 8).toString('base64');

/** R2 in het geheugen: put/get/list en multipart. */
function r2() {
  const store = new Map();
  const obj = (k) => {
    const b = store.get(k);
    return b && { key: k, size: b.length, body: new Blob([b]).stream(), arrayBuffer: async () => b.buffer.slice(b.byteOffset, b.byteOffset + b.length) };
  };
  return {
    store,
    async put(k, v) {
      const b = typeof v === 'string' ? new TextEncoder().encode(v) : v instanceof Uint8Array ? v : new Uint8Array(await new Response(v).arrayBuffer());
      store.set(k, b);
    },
    async get(k) {
      return obj(k) ?? null;
    },
    async list({ prefix }) {
      return { objects: [...store.keys()].filter((k) => k.startsWith(prefix)).map((k) => ({ key: k })) };
    },
    async createMultipartUpload(k) {
      const parts = [];
      return {
        uploadPart: async (n, data) => (parts[n - 1] = new Uint8Array(data), { partNumber: n }),
        complete: async () => store.set(k, new Uint8Array(await new Blob(parts).arrayBuffer())),
        abort: async () => {},
      };
    },
  };
}

async function seeded() {
  const db = d1();
  addUser(db, 'u1');
  addUser(db, 'u2');
  const rows = Array.from({ length: 1200 }, (_, i) => ({ id: `r${i}`, day: '2026-10-25', meal: 1, food_ref: 'ciqual:1', name: `Ding ${i} é ✓`, grams: 1.5 * i, quantity: 1, nutrients: JSON.stringify({ energy: i }), created_at: 1, updated_at: 1000 + i, deleted: 0 }));
  for (let i = 0; i < rows.length; i += 400) await push(db, 'u1', 'diary', rows.slice(i, i + 400));
  await push(db, 'u2', 'settings', [{ key: 'profile', value: '{"a":1}', updated_at: 5 }]);
  db.raw.prepare("INSERT INTO account (id, \"accountId\", \"providerId\", \"userId\", password, \"createdAt\", \"updatedAt\") VALUES ('u1', 'u1', 'credential', 'u1', 'hash', 'x', 'x')").run();
  db.raw.prepare("INSERT INTO session (id, \"expiresAt\", token, \"createdAt\", \"updatedAt\", \"userId\") VALUES ('s', 'x', 't', 'x', 'x', 'u1')").run();
  return db;
}
const bytes = async (stream) => new Uint8Array(await new Response(stream).arrayBuffer());

test('back-up en terugzetten in een lege database: exact dezelfde inhoud (ook server_seq en de teller)', async () => {
  const src = await seeded();
  const { stream, manifest } = await makeBackup(src, KEY, new Date('2026-10-25T03:00:00Z'), { block: 4096 });
  const file = await bytes(stream);
  assert.equal(manifest.tables.diary.rows, 1200);
  assert.ok(!('session' in manifest.tables), 'sessies niet in de back-up');
  // Leesbare tekst staat nergens in het bestand
  assert.ok(!Buffer.from(file).includes('Ding 1'));
  const dst = d1();
  const m = await restoreBackup(dst, file, KEY);
  assert.deepEqual(await verifyRestore(dst, m), []);
  assert.deepEqual(await fingerprint(dst, await backupTables(dst)), await fingerprint(src, await backupTables(src)));
  assert.equal(dst.raw.prepare('SELECT seq FROM sync_seq').get().seq, src.raw.prepare('SELECT seq FROM sync_seq').get().seq);
  assert.equal(dst.raw.prepare('SELECT active FROM import_mode').get().active, 0);
  // Opnieuw terugzetten (over de vorige kopie heen) blijft gelijk
  await restoreBackup(dst, file, KEY);
  assert.deepEqual(await verifyRestore(dst, m), []);
});

test('verkeerde sleutel, gewijzigde of ingekorte back-up: geweigerd', async () => {
  const src = await seeded();
  const file = await bytes((await makeBackup(src, KEY, new Date(), { block: 4096 })).stream);
  const drain = async (f, k) => {
    for await (const _ of readBackup(f, k));
  };
  await assert.rejects(drain(file, OTHER));
  const flipped = file.slice();
  flipped[200] ^= 1;
  await assert.rejects(drain(flipped, KEY));
  // Laatste blok weg: het voorlaatste is niet als laatste versleuteld
  let pos = 4;
  let lastStart = 4;
  while (pos < file.length) {
    lastStart = pos;
    pos += 16 + new DataView(file.buffer, file.byteOffset + pos, 4).getUint32(0);
  }
  await assert.rejects(drain(file.slice(0, lastStart), KEY));
  await assert.rejects(drain(file.slice(0, file.length - 10), KEY));
});

test('een verschil na terugzetten wordt gevonden', async () => {
  const src = await seeded();
  const { stream } = await makeBackup(src, KEY);
  const dst = d1();
  const m = await restoreBackup(dst, await bytes(stream), KEY);
  dst.raw.exec("UPDATE import_mode SET active = 1; UPDATE diary SET grams = 999 WHERE id = 'r5'; UPDATE import_mode SET active = 0");
  assert.deepEqual(await verifyRestore(dst, m), ['diary: inhoud verschilt']);
});

test('nachtelijke taak naar R2 (daily + manifest, op de 1e ook monthly) en de maandelijkse hersteltest', async () => {
  const env = { DB: await seeded(), BACKUP: r2(), BACKUP_KEY: KEY, RESTORE_DB: d1() };
  await dailyBackup(env, new Date('2026-11-01T03:00:00Z'));
  assert.deepEqual([...env.BACKUP.store.keys()].sort(), ['daily/2026-11-01.mmb', 'daily/2026-11-01.mmb.json', 'monthly/2026-11.mmb']);
  const r = await restoreCheck(env, new Date('2026-11-01T04:00:00Z'));
  assert.equal(r.ok, true);
  assert.equal(r.backup, 'daily/2026-11-01.mmb');
  assert.ok(env.BACKUP.store.has('checks/2026-11-01.json'));
});

test('mislukt: waarschuwing naar de beheerder', async () => {
  const sent = [];
  const env = { DB: await seeded(), BACKUP: r2(), BACKUP_KEY: 'te-kort', ADMIN_EMAIL: 'beheer@example.org', EMAIL: { send: async (m) => sent.push(m) } };
  await assert.rejects(dailyBackup(env));
  assert.equal(sent[0].subject, '[MacroMatrix] Back-up mislukt');
});
