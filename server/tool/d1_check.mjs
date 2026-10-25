// De synctriggers op een echte D1 nakijken (zelfde kernproeven als test/schema.test.mjs, die met node:sqlite draait).
// Maakt een tijdelijk testaccount en verwijdert het daarna weer (ON DELETE CASCADE).
//   node tool/d1_check.mjs --env staging [--local]
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';

const args = process.argv.slice(2);
const flags = [args.includes('--local') ? '--local' : '--remote', ...(args.includes('--env') ? ['--env', args[args.indexOf('--env') + 1]] : [])];
const q = (sql) => {
  try {
    return JSON.parse(execFileSync('npx', ['wrangler', 'd1', 'execute', 'DB', ...flags, '--json', '--command', sql], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })).at(-1).results;
  } catch (e) {
    throw new Error(String(e.stdout || e.message).slice(0, 400));
  }
};

const id = `d1check-${Date.now()}`;
const now = new Date().toISOString();
const push = (updatedAt, grams) =>
  q(`INSERT INTO diary (user_id, id, day, meal, food_ref, name, grams, quantity, nutrients, created_at, updated_at)
     VALUES ('${id}', 'r1', '2026-10-25', 1, 'test:1', 'test', ${grams}, 1, '{}', 1, ${updatedAt})
     ON CONFLICT (user_id, id) DO UPDATE SET grams = excluded.grams, updated_at = excluded.updated_at`);
const row = () => q(`SELECT grams, updated_at, server_seq FROM diary WHERE user_id = '${id}'`)[0];

q(`INSERT INTO "user" (id, name, email, emailVerified, createdAt, updatedAt) VALUES ('${id}', '', '${id}@example.invalid', 0, '${now}', '${now}')`);
try {
  push(1000, 10);
  const a = row();
  assert.ok(a.server_seq > 0, 'server_seq toegekend');
  push(500, 1);
  assert.deepEqual(row(), a, 'oudere versie genegeerd');
  push(2000, 20);
  const b = row();
  assert.ok(b.grams === 20 && b.server_seq > a.server_seq, 'nieuwere versie + hoger server_seq');
  const t = Date.now();
  push(t + 3_600_000, 30);
  assert.ok(row().updated_at <= Date.now() + 300_000 && row().updated_at >= t + 290_000, 'klok begrensd op nu + 5 min');
  assert.throws(() => q(`UPDATE diary SET user_id = 'iemand' WHERE user_id = '${id}'`), /user_id/, 'user_id vast');
  assert.equal(q('SELECT active FROM import_mode')[0].active, 0, 'importmodus uit');
  console.log('d1_check: alle proeven geslaagd');
} finally {
  q(`DELETE FROM "user" WHERE id = '${id}'`);
  assert.equal(q(`SELECT count(*) n FROM diary WHERE user_id = '${id}'`)[0].n, 0, 'opgeruimd via cascade');
}
