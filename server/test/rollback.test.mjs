// Terugvalplan (tool/d1_to_supabase.mjs) van begin tot eind: Supabase (PGlite met alle migraties) → omschakeling
// (import naar D1) → wijzigingen op de eigen server → terug naar Supabase → nakijken in Supabase.
// Nodig: PGlite (npm-pakket @electric-sql/pglite), pad in PGLITE of standaard naast de repo; anders overgeslagen.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { d1 } from './d1.mjs';
import { push } from '../src/sync.js';
import { importSql } from '../tool/supabase_to_d1.mjs';
import { rollbackSql } from '../tool/d1_to_supabase.mjs';

const PGLITE = process.env.PGLITE ?? `${process.env.HOME}/Documents/Apps/voedingsapp-data/tools/pglite/dist/index.js`;
const MIGRATIONS = new URL('../../supabase/migrations/', import.meta.url);
const [U1, U2, U3, U4] = ['11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444'];

/** Supabase nagebootst: auth-schema met users en identities, en alle migraties (behalve pg_cron). */
async function supabase() {
  const { PGlite } = await import(PGLITE);
  const db = new PGlite();
  await db.exec(`
    create role anon nologin; create role authenticated nologin; create role service_role nologin; create role supabase_auth_admin nologin;
    create schema auth; create schema cron;
    create table auth.users (id uuid primary key, instance_id uuid, aud text, role text, email text, encrypted_password text,
      email_confirmed_at timestamptz, raw_app_meta_data jsonb, raw_user_meta_data jsonb, created_at timestamptz default now(), updated_at timestamptz default now());
    create table auth.identities (id uuid primary key default gen_random_uuid(), provider_id text, user_id uuid references auth.users(id) on delete cascade,
      identity_data jsonb, provider text, created_at timestamptz, updated_at timestamptz, unique (provider_id, provider));
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create publication supabase_realtime;
    grant usage on schema public, auth to anon, authenticated;`);
  for (const f of readdirSync(MIGRATIONS).sort()) {
    if (f.includes('cleanup_unconfirmed')) continue;
    await db.exec(readFileSync(new URL(f, MIGRATIONS), 'utf8'));
  }
  return db;
}

/** Zoals exportSnapshot in tool/supabase_to_d1.mjs, maar op PGlite. */
async function snapshotOf(pg) {
  const q = async (s) => (await pg.query(s)).rows;
  const columns = await q("select table_name t, column_name c, data_type d from information_schema.columns where table_schema = 'public' order by table_name, ordinal_position");
  const keys = await q(`select c.relname t, a.attname c from pg_constraint con join pg_class c on c.oid = con.conrelid
    cross join unnest(con.conkey) with ordinality k(attnum, ord) join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
    where con.contype = 'p' and con.connamespace = 'public'::regnamespace order by c.relname, k.ord`);
  const schema = {};
  for (const { t, c, d } of columns) (schema[t] ??= { columns: [], key: [] }).columns.push({ name: c, type: d });
  for (const { t, c } of keys) schema[t].key.push(c);
  const tables = {};
  for (const t of Object.keys(schema)) {
    if (t === 'signup_ips') continue;
    tables[t] = (await q(`select coalesce(json_agg(x), '[]'::json) j from (select * from public."${t}") x`))[0].j;
  }
  const users = (await q(`select coalesce(json_agg(x), '[]'::json) j from (select id, email, encrypted_password, email_confirmed_at, created_at, updated_at,
    raw_user_meta_data ->> 'terms_version' terms_version, raw_user_meta_data ->> 'terms_accepted_at' terms_accepted_at from auth.users) x`))[0].j;
  return { at: new Date().toISOString(), schema, users, tables };
}

const entry = (id, at, extra = {}) => ({ id, day: '2026-11-02', meal: 1, food_ref: 'ciqual:1', name: 'Banaan', grams: 100, quantity: 1, nutrients: '{}', created_at: 1, updated_at: at, deleted: 0, ...extra });

test('terugval: wijzigingen na de omschakeling komen juist in Supabase', { skip: !existsSync(PGLITE) && 'PGlite niet gevonden' }, async () => {
  const pg = await supabase();
  const q = async (s, p) => (await pg.query(s, p)).rows;
  // Supabase vóór de omschakeling
  await pg.exec(`insert into auth.users (id, email, encrypted_password, email_confirmed_at) values
    ('${U1}', 'a@example.org', '$2a$10$oud', now()), ('${U2}', 'b@example.org', '$2a$10$oud', null), ('${U3}', 'c@example.org', '$2a$10$oud', now())`);
  await pg.exec(`insert into public.diary (user_id, id, day, meal, food_ref, name, grams, quantity, nutrients, created_at, updated_at)
    values ('${U1}', 'e1', '2026-11-01', 1, 'x', 'Appel', 100, 1, '{}', 1, 1000), ('${U3}', 'e9', '2026-11-01', 1, 'x', 'Peer', 50, 1, '{}', 1, 1000)`);
  await pg.exec(`insert into public.friendships (requester, addressee) values ('${U1}', '${U2}')`);
  const before = await snapshotOf(pg);

  // Omschakeling: alles naar D1 (zoals tool/supabase_to_d1.mjs)
  const db = d1();
  db.raw.exec(importSql(before));
  const cutoverSeq = db.raw.prepare('SELECT seq FROM sync_seq').get().seq;

  // Op de eigen server na de omschakeling
  const t = Date.now();
  await push(db, U1, 'diary', [entry('e1', t, { grams: 150 }), entry('e2', t)]);
  db.raw.exec(`UPDATE friendships SET accepted = 1 WHERE requester = '${U1}'`);
  db.raw.exec(`UPDATE "user" SET "emailVerified" = 1, "updatedAt" = '2026-11-02T10:00:00.000Z' WHERE id = '${U2}'`);
  db.raw.exec(`DELETE FROM "user" WHERE id = '${U3}'`);
  db.raw.exec(`INSERT INTO "user" (id, name, email, "emailVerified", "createdAt", "updatedAt", "termsVersion") VALUES ('${U4}', '', 'd@example.org', 1, '2026-11-02T09:00:00.000Z', '2026-11-02T09:00:00.000Z', '2026-10-17');
    INSERT INTO account (id, "accountId", "providerId", "userId", password, "createdAt", "updatedAt") VALUES ('${U4}', '${U4}', 'credential', '${U4}', 'scrypt:hash', 'x', 'x')`);
  await push(db, U4, 'notes', [{ day: '2026-11-02', text: "nieuw' account", updated_at: t }]);
  db.raw.exec(`INSERT INTO pro_status (user_id, until, source) VALUES ('${U4}', '2027-01-01T00:00:00.000Z', 'play')`);

  // Terug naar Supabase
  const all = (s) => db.raw.prepare(s).all().map((r) => ({ ...r }));
  const now = { user: all('SELECT * FROM "user"'), account: all('SELECT * FROM account'), tables: {} };
  for (const tb of Object.keys(before.schema)) if (tb !== 'signup_ips') now.tables[tb] = all(`SELECT * FROM "${tb}"`);
  const cutoverTs = (await q("select max(server_ts) m from public.diary"))[0].m;
  await pg.exec(rollbackSql({ snapshot: before, d1: now, cutoverSeq }));

  const diary = await q(`select id, grams, server_ts from public.diary where user_id = '${U1}' order by id`);
  assert.deepEqual(diary.map((r) => [r.id, r.grams]), [['e1', 150], ['e2', 100]]);
  assert.ok(diary.every((r) => r.server_ts > cutoverTs), 'nieuwe server_ts: de toestellen halen ze op');
  assert.equal((await q('select accepted from public.friendships'))[0].accepted, true);
  assert.ok((await q(`select email_confirmed_at from auth.users where id = '${U2}'`))[0].email_confirmed_at);
  assert.equal((await q(`select count(*)::int n from auth.users where id = '${U3}'`))[0].n, 0);
  assert.equal((await q(`select count(*)::int n from public.diary where user_id = '${U3}'`))[0].n, 0);
  const [u4] = await q(`select email, encrypted_password, raw_user_meta_data ->> 'terms_version' tv from auth.users where id = '${U4}'`);
  assert.deepEqual({ ...u4 }, { email: 'd@example.org', encrypted_password: '', tv: '2026-10-17' });
  assert.equal((await q(`select count(*)::int n from auth.identities where user_id = '${U4}'`))[0].n, 1);
  assert.equal((await q(`select text from public.notes where user_id = '${U4}'`))[0].text, "nieuw' account");
  assert.equal((await q(`select source from public.pro_status where user_id = '${U4}'`))[0].source, 'play');
});
