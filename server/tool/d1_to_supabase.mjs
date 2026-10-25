// Terugvalplan (fase 7): alles wat na de omschakeling op de eigen server gebeurde, terug naar Supabase zetten.
// Maakt Postgres-SQL voor Supabase; uitvoeren gebeurt apart (Management API of psql), pas na toestemming.
//
//   node tool/d1_to_supabase.mjs <map met de snapshot van de omschakeling> --env <env> --cutover-seq <N> --sql uit.sql
//
// - De snapshot (snapshot.json van supabase_to_d1.mjs bij de omschakeling) geeft de types en welke accounts er toen
//   waren; --cutover-seq is sync_seq.seq direct na die laatste import.
// - Synctabellen: alleen rijen met server_seq > N (alles daarvoor stond al in Supabase, en daar wordt nooit hard
//   verwijderd). Gewone upsert, zodat sync_stamp server_ts zet en de toestellen ze ophalen.
// - De andere tabellen (vrienden, battles, Supporter, tellers, …): een volledige kopie van de eigen server, zonder
//   triggers (die rijen hebben geen betrouwbaar wijzigingstijdstip). Supabase stond bevroren, dus dat is juist.
// - Accounts: nieuwe accounts worden aangemaakt (zonder bruikbaar wachtwoord: de hash van de eigen server kan Supabase
//   niet lezen; die mensen kiezen "wachtwoord vergeten"), verwijderde accounts worden verwijderd (cascade).
// Beperking: een wachtwoord dat na de omschakeling gewijzigd werd, is in Supabase weer het oude.
import { execFileSync } from 'node:child_process';
import { chmodSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { SYNC } from './supabase_to_d1.mjs';

const SKIP = new Set(['signup_ips']);
const FIRST = ['features', 'roadmap_items', 'challenges'];
const INSTANCE = '00000000-0000-0000-0000-000000000000';

const pgLit = (v, type) => {
  if (v === null || v === undefined) return 'NULL';
  if (type === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') return Number.isFinite(v) ? String(v) : 'NULL';
  return `'${String(v).replaceAll("'", "''")}'`;
};
const ident = (c) => `"${c}"`;

/**
 * De SQL voor Supabase. [snapshot]: de snapshot van de omschakeling; [d1]: { user, account, tables: { naam: rijen } }
 * zoals nu op de eigen server; [cutoverSeq]: sync_seq na de laatste import.
 */
export function rollbackSql({ snapshot, d1, cutoverSeq }) {
  const out = ['begin;'];
  const before = new Set(snapshot.users.map((u) => u.id));
  const now = new Set(d1.user.map((u) => u.id));
  const account = new Map(d1.account.filter((a) => a.providerId === 'credential').map((a) => [a.userId, a]));

  // 1. Accounts die na de omschakeling verwijderd werden (cascade ruimt hun rijen op)
  const gone = [...before].filter((id) => !now.has(id));
  if (gone.length) out.push(`delete from auth.users where id in (${gone.map((id) => pgLit(id)).join(', ')});`);

  // 2. Nieuwe accounts (met e-mail-identiteit, zoals Supabase ze zelf maakt) en bevestigingen na de omschakeling
  const confirmedAtCutover = new Set(snapshot.users.filter((u) => u.email_confirmed_at).map((u) => u.id));
  for (const u of d1.user) {
    if (!before.has(u.id)) {
      const meta = { ...(u.termsVersion ? { terms_version: u.termsVersion } : {}), ...(u.termsAcceptedAt ? { terms_accepted_at: u.termsAcceptedAt } : {}) };
      const pw = account.get(u.id)?.password;
      out.push(
        `insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values (` +
          [u.id, INSTANCE, 'authenticated', 'authenticated', u.email, pw && pw.startsWith('$2') ? pw : ''].map((v) => pgLit(v)).join(', ') +
          `, ${u.emailVerified ? pgLit(u.updatedAt) : 'NULL'}, '{"provider":"email","providers":["email"]}', ${pgLit(JSON.stringify(meta))}, ${pgLit(u.createdAt)}, ${pgLit(u.updatedAt)});`,
        `insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at) values (` +
          `${pgLit(u.id)}, ${pgLit(u.id)}, ${pgLit(JSON.stringify({ sub: u.id, email: u.email, email_verified: !!u.emailVerified }))}, 'email', ${pgLit(u.createdAt)}, ${pgLit(u.updatedAt)});`,
      );
    } else if (u.emailVerified && !confirmedAtCutover.has(u.id)) {
      out.push(`update auth.users set email_confirmed_at = ${pgLit(u.updatedAt)} where id = ${pgLit(u.id)} and email_confirmed_at is null;`);
    }
  }

  // 3. De andere tabellen: volledige kopie, zonder triggers (en dus ook zonder verwijzingscontroles; de gegevens komen
  // uit een consistente database)
  const tables = Object.keys(snapshot.schema).filter((t) => !SYNC.includes(t) && !SKIP.has(t));
  const order = [...FIRST.filter((t) => tables.includes(t)), ...tables.filter((t) => !FIRST.includes(t)).sort()];
  out.push('set local session_replication_role = replica;');
  for (const t of [...order].reverse()) out.push(`delete from public.${ident(t)};`);
  for (const t of order) {
    const cols = snapshot.schema[t].columns;
    for (const r of d1.tables[t] ?? []) {
      out.push(`insert into public.${ident(t)} (${cols.map((c) => ident(c.name)).join(', ')}) values (${cols.map((c) => pgLit(r[c.name], c.type)).join(', ')});`);
    }
  }
  out.push('set local session_replication_role = origin;');

  // 4. Synctabellen: wat na de omschakeling binnenkwam
  for (const t of SYNC) {
    const { columns, key } = snapshot.schema[t];
    const cols = columns.filter((c) => c.name !== 'server_ts');
    const conflict = key.map(ident).join(', ');
    const set = cols.filter((c) => !key.includes(c.name)).map((c) => `${ident(c.name)} = excluded.${ident(c.name)}`).join(', ');
    for (const r of (d1.tables[t] ?? []).filter((r) => r.server_seq > cutoverSeq)) {
      out.push(
        `insert into public.${ident(t)} (${cols.map((c) => ident(c.name)).join(', ')}) values (${cols.map((c) => pgLit(r[c.name], c.type)).join(', ')}) ` +
          `on conflict (${conflict}) do update set ${set};`,
      );
    }
  }
  out.push('commit;');
  return out.join('\n') + '\n';
}

// ── Opdrachtregel: de eigen server uitlezen via wrangler ──

if (import.meta.url === `file://${process.argv[1]}`) {
  const [dir, ...rest] = process.argv.slice(2);
  const opt = (n) => (rest.includes(n) ? rest[rest.indexOf(n) + 1] : null);
  if (!dir || !opt('--env') || !opt('--cutover-seq') || !opt('--sql')) {
    console.error('Gebruik: d1_to_supabase.mjs <snapshotmap> --env <env> --cutover-seq <N> --sql uit.sql [--local]');
    process.exit(2);
  }
  // Productie is de bovenste laag van wrangler.jsonc (geen --env)
  const flags = [rest.includes('--local') ? '--local' : '--remote', ...(opt('--env') === 'production' ? [] : ['--env', opt('--env')])];
  const q = (s) => JSON.parse(execFileSync('npx', ['wrangler', 'd1', 'execute', 'DB', ...flags, '--json', '--command', s], { encoding: 'utf8', maxBuffer: 1 << 30, stdio: ['ignore', 'pipe', 'pipe'] })).at(-1).results;
  const snapshot = JSON.parse(readFileSync(join(dir, 'snapshot.json'), 'utf8'));
  const d1 = { user: q('SELECT * FROM "user"'), account: q('SELECT * FROM account'), tables: {} };
  for (const t of Object.keys(snapshot.schema)) if (!SKIP.has(t)) d1.tables[t] = q(`SELECT * FROM "${t}"`);
  writeFileSync(opt('--sql'), rollbackSql({ snapshot, d1, cutoverSeq: Number(opt('--cutover-seq')) }));
  chmodSync(opt('--sql'), 0o600);
  console.log(`SQL voor Supabase: ${opt('--sql')} (nog niet uitgevoerd)`);
}
