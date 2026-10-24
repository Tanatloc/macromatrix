// Gebruik: node supabase/tests/moderation_test.mjs <pad>/pglite/dist/index.js
// Alle migraties na elkaar in PGlite (Postgres in WebAssembly, nagebootst auth-schema), daarna het woordfilter op
// namen en titels, uitdagingen melden en geblokkeerde deelnemers in challenge_list (migratie moderation.sql).
// pg_cron (opruimen) en de aanmeldhook draaien niet in PGlite: die twee migraties worden overgeslagen.
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
const q = async (sql, params) => (await db.query(sql, params)).rows;
const ok = (cond, msg) => { if (!cond) { console.log('MISLUKT:', msg); process.exitCode = 1; } else console.log('ok:', msg); };
const fails = async (f) => { try { await f(); return null; } catch (e) { return e.message; } };

await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin;
  create schema auth;
  create table auth.users (id uuid primary key, email text);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema public, auth to anon, authenticated;
  grant execute on function auth.uid() to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
  create publication supabase_realtime;
`);
const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'migrations');
const skip = ['20261016010000_cleanup_unconfirmed.sql', '20261104000000_signup_ip_limit.sql'];
for (const f of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
  if (skip.includes(f)) continue;
  try {
    await db.exec(readFileSync(join(dir, f), 'utf8'));
  } catch (e) {
    console.log('MISLUKT: migratie', f, e.message);
    process.exit(1);
  }
}
console.log('ok: alle migraties lopen zonder fouten');

// ── Het filter zelf ──
const blocked = async (t) => (await q('select public.text_blocked($1) b', [t]))[0].b;
for (const t of ['Fuck you nazi', 'sh1t', 'B1tch', 'FUUUCK', 'shit', 'motherfucker', 'kankerlijer', 'Klootzak!', 'sieg  heil', 'Kut-dag', 'heil hitler'])
  ok(await blocked(t), `geweigerd: ${t}`);
for (const t of ['Scunthorpe', 'Shiitake week', 'shitake', 'Catering', 'Dick', 'Vezels 30 dagen', 'Analyse', 'Sluiten', 'Wankel', 'Kanker-vrij eten', '', null, 'Anna 🥦'])
  ok(!(await blocked(t)), `toegelaten: ${t}`);

const u1 = '11111111-1111-1111-1111-111111111111', u2 = '22222222-2222-2222-2222-222222222222', u3 = '33333333-3333-3333-3333-333333333333';
await db.exec(`insert into auth.users values ('${u1}', 'a@x.be'), ('${u2}', 'b@x.be'), ('${u3}', 'c@x.be')`);
const as = async (uid, fn) => {
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${uid}', false);`);
  try { return await fn(); } finally { await db.exec('reset role'); }
};

// ── friend_me ──
await as(u1, async () => {
  const err = await fails(() => q(`select * from public.friend_me('Fuck you nazi')`));
  ok(err === 'name_not_allowed', 'friend_me weigert een scheldnaam met name_not_allowed');
  ok((await q(`select * from public.friend_me('Anna')`))[0].name === 'Anna', 'friend_me bewaart een gewone naam');
  ok((await q(`select * from public.friend_me(null, null, 3)`))[0].name === 'Anna', 'zonder naam blijft de naam staan');
  ok((await fails(() => q(`select * from public.friend_me('Shit')`))) === 'name_not_allowed', 'ook bij een bestaand profiel');
  ok((await q(`select * from public.friend_me()`))[0].name === 'Anna', 'de oude naam blijft na een weigering');
});
await as(u2, () => q(`select * from public.friend_me('Bob')`));
await as(u3, () => q(`select * from public.friend_me('Cleo')`));
// u1 en u2 vrienden, u3 niet (komt in de uitdaging via u2)
await db.exec(`insert into public.friendships (requester, addressee, accepted) values ('${u1}', '${u2}', true), ('${u2}', '${u3}', true)`);

// ── challenge_create ──
const create = (title, invite) => q(
  `select public.challenge_create('custom', $1, 'fiber', 'min', 25, 14, 14, current_date, $2::uuid[]) id`, [title, invite]);
let cid;
await as(u1, async () => {
  ok((await fails(() => create('Kut uitdaging', '{}'))) === 'title_not_allowed', 'challenge_create weigert een scheldtitel');
  cid = (await create('Vezelweek', `{${u2}}`))[0].id;
  ok(!!cid, 'challenge_create met een gewone titel lukt');
  ok(!!(await create(null, '{}'))[0].id, 'zonder titel lukt ook');
});
await as(u2, async () => {
  await q(`select public.challenge_respond($1, true)`, [cid]);
  ok((await q(`select public.challenge_invite($1, $2) r`, [cid, u3]))[0].r === 'invited', 'u2 nodigt zijn vriend u3 uit (geen vriend van u1)');
});
await as(u3, () => q(`select public.challenge_respond($1, true)`, [cid]));

// ── Melden ──
await as(u3, async () => {
  ok((await q(`select public.challenge_report($1, 'rare titel') r`, [cid]))[0].r === 'reported', 'deelnemer meldt de uitdaging');
  ok((await q(`select public.friend_report($1, 'harassment', null) r`, [u1]))[0].r === 'reported', 'deelnemer meldt een medespeler die geen vriend is');
});
const [rep] = await q(`select reported, reason, note, challenge_id, challenge_title, reported_name from public.user_reports where reason = 'challenge_title'`);
ok(rep.reported === u1 && rep.challenge_id === cid && rep.challenge_title === 'Vezelweek' && rep.note === 'rare titel' && rep.reported_name === 'Anna',
  'de melding bewaart maker, uitdaging, titel en notitie');
await as(u1, async () => {
  ok((await q(`select public.challenge_report($1, null) r`, [cid]))[0].r === 'not_found', 'je eigen uitdaging meld je niet');
});
const outsider = '44444444-4444-4444-4444-444444444444';
await db.exec(`insert into auth.users values ('${outsider}', 'd@x.be')`);
await as(outsider, async () => {
  ok((await q(`select public.challenge_report($1, null) r`, [cid]))[0].r === 'not_found', 'wie niet in de uitdaging zit, kan ze niet melden');
});
await as(u3, async () => {
  for (let i = 0; i < 8; i++) await q(`select public.challenge_report($1, null)`, [cid]);
  ok((await q(`select public.challenge_report($1, null) r`, [cid]))[0].r === 'limit', 'hoogstens 10 meldingen per dag, samen met friend_report');
});
await as(u1, async () => {
  ok(!!(await fails(() => q(`insert into public.user_reports (reporter, reported, reason) values ($1, $2, 'challenge_title')`, [u1, u3]))),
    'meldingen niet rechtstreeks schrijven');
});

// ── Blokkeren in een uitdaging ──
await as(u3, async () => {
  const before = (await q(`select distinct member from public.challenge_list() where id = $1`, [cid])).map((r) => r.member);
  ok(before.includes(u1), 'u3 ziet u1 in de uitdaging');
  await q(`select public.friend_block($1)`, [u1]);
  const after = (await q(`select distinct member from public.challenge_list() where id = $1`, [cid])).map((r) => r.member);
  ok(!after.includes(u1) && after.includes(u3) && after.includes(u2), 'na blokkeren verdwijnt u1 uit de ranglijst van u3, de rest blijft');
});
await as(u1, async () => {
  const members = (await q(`select distinct member from public.challenge_list() where id = $1`, [cid])).map((r) => r.member);
  ok(members.includes(u3), 'wie geblokkeerd is, merkt niets: u1 ziet u3 nog');
});
