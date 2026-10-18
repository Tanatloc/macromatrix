// Gebruik: PGlite downloaden (npm-pakket @electric-sql/pglite, bv. via "npm pack" of de tarball van registry.npmjs.org)
// en dan: node supabase/tests/rls_test.mjs <pad>/package/dist/index.js supabase/migrations/20261016000000_init.sql
// Supabase-migratie testen in PGlite (Postgres in WebAssembly) met een nagebootst auth-schema.
import { readFileSync } from 'node:fs';
const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
const q = async (sql, params) => (await db.query(sql, params)).rows;
const ok = (cond, msg) => { if (!cond) { console.log('MISLUKT:', msg); process.exitCode = 1; } else console.log('ok:', msg); };

await db.exec(`
  create role anon nologin; create role authenticated nologin;
  create schema auth;
  create table auth.users (id uuid primary key, email text);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema public, auth to anon, authenticated;
  grant execute on function auth.uid() to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
`);
await db.exec(readFileSync(process.argv[3], 'utf8'));
console.log('ok: migratie loopt zonder fouten');

const u1 = '11111111-1111-1111-1111-111111111111', u2 = '22222222-2222-2222-2222-222222222222';
await db.exec(`insert into auth.users values ('${u1}', 'a@x.be'), ('${u2}', 'b@x.be')`);
const as = async (uid, fn) => {
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${uid}', false);`);
  try { return await fn(); } finally { await db.exec('reset role'); }
};
const upsert = (id, grams, updated) => q(
  `insert into public.diary (user_id, id, day, meal, food_ref, name, grams, quantity, nutrients, created_at, updated_at)
   values ($1, $2, '2026-10-16', 0, 'x', 'Banaan', $3, $3, '{}', 1, $4)
   on conflict (user_id, id) do update set grams = excluded.grams, quantity = excluded.quantity, updated_at = excluded.updated_at, deleted = excluded.deleted`,
  [u1, id, grams, updated]);

await as(u1, async () => {
  await upsert('e1', 100, 1000);
  const [r1] = await q(`select grams, server_ts from public.diary where id = 'e1'`);
  ok(r1.grams === 100, 'invoegen als eigen gebruiker');
  await upsert('e1', 150, 2000);
  const [r2] = await q(`select grams, server_ts from public.diary where id = 'e1'`);
  ok(r2.grams === 150 && r2.server_ts > r1.server_ts, 'nieuwere versie overschrijft en krijgt een nieuwe server_ts');
  await upsert('e1', 50, 1500);
  const [r3] = await q(`select grams, server_ts from public.diary where id = 'e1'`);
  ok(r3.grams === 150 && +r3.server_ts === +r2.server_ts, 'oudere versie wordt genegeerd');
  let refused = false;
  try { await q(`insert into public.diary (user_id, id, day, meal, food_ref, name, grams, quantity, nutrients, created_at, updated_at) values ($1,'x','d',0,'x','x',1,1,'{}',1,1)`, [u2]); } catch { refused = true; }
  ok(refused, 'rijen voor een andere gebruiker invoegen mag niet');
  let noDelete = false;
  const del = await db.query(`delete from public.diary where id = 'e1'`);
  noDelete = del.affectedRows === 0;
  ok(noDelete, 'hard verwijderen kan niet (alleen zacht)');
  // Notities en instellingen hebben een andere sleutel
  await q(`insert into public.notes (user_id, day, text, updated_at) values ($1, '2026-10-16', 'hoi', 1) on conflict (user_id, day) do update set text = excluded.text, updated_at = excluded.updated_at`, [u1]);
  await q(`insert into public.fasts (user_id, id, start, "end", goal_hours, updated_at) values ($1, 'f1', 1, 2, 16, 1)`, [u1]);
  ok((await q(`select count(*)::int n from public.notes`))[0].n === 1, 'notities met dag als sleutel');
});

await as(u2, async () => {
  ok((await q(`select count(*)::int n from public.diary`))[0].n === 0, 'gebruiker 2 ziet de rijen van gebruiker 1 niet');
  const upd = await db.query(`update public.diary set grams = 1 where id = 'e1'`);
  ok(upd.affectedRows === 0, 'gebruiker 2 kan de rijen van gebruiker 1 niet wijzigen');
});

await db.exec(`set role anon; select set_config('request.jwt.claim.sub', '', false);`);
let anonBlocked = false;
try { await q(`select * from public.diary`); } catch { anonBlocked = true; }
await db.exec('reset role');
ok(anonBlocked, 'niet ingelogd: geen toegang');

await as(u1, async () => { await q('select public.delete_account()'); });
ok((await q(`select count(*)::int n from public.diary`))[0].n === 0 && (await q(`select count(*)::int n from auth.users where id = '${u1}'`))[0].n === 0,
  'account verwijderen wist de gebruiker en al zijn gegevens');
