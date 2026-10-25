// Supabase -> D1: alle gegevens kopiëren en daarna rij per rij vergelijken. Opnieuw uitvoeren mag: de D1 wordt dan
// weer een exacte kopie (geen dubbels; sessies van Better Auth blijven staan, behalve van verdwenen accounts).
//
//   node tool/supabase_to_d1.mjs export <map>                       Supabase -> <map>/snapshot.json (alleen lezen)
//   node tool/supabase_to_d1.mjs sql <map>                          snapshot -> <map>/import.sql
//   node tool/supabase_to_d1.mjs load <map> --env staging [--local] import.sql uitvoeren op die D1
//   node tool/supabase_to_d1.mjs compare <map> --env staging [--local]
//   node tool/supabase_to_d1.mjs all <map> --env staging [--local]  alles na elkaar
//
// Nodig: SUPABASE_ACCESS_TOKEN en SUPABASE_PROJECT (export); CLOUDFLARE_API_TOKEN en CLOUDFLARE_ACCOUNT_ID (remote).
// De snapshot bevat persoonsgegevens en wachtwoord-hashes: <map> hoort buiten elke repo en elk archief.
import { execFileSync } from 'node:child_process';
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// Gesynchroniseerde tabellen: server_ts wordt server_seq
export const SYNC = ['settings', 'foods', 'diary', 'meals', 'biometrics', 'notes', 'exercise', 'fasts', 'repeats'];
// Eerst invoegen (andere tabellen verwijzen ernaar); verwijderen in omgekeerde volgorde
const FIRST = ['features', 'roadmap_items', 'challenges'];
// Niet meenemen: kortstondige IP-hashes voor de registratielimiet
const SKIP = new Set(['signup_ips']);
// Langere tekst in stukken (D1: hoogstens 100 KB per SQL-opdracht)
const CHUNK = 30000;

// ── Export (Supabase Management API, alleen lezen) ──

async function pg(sql) {
  const project = process.env.SUPABASE_PROJECT ?? 'hvqbqgxpksxmavopngap';
  const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql, read_only: true }),
  });
  const body = await r.json();
  if (!r.ok || !Array.isArray(body)) throw new Error(`Supabase: ${r.status} ${JSON.stringify(body).slice(0, 300)}`);
  return body;
}

async function exportSnapshot(dir) {
  const columns = await pg(
    "select table_name t, column_name c, data_type d from information_schema.columns where table_schema = 'public' order by table_name, ordinal_position",
  );
  const keys = await pg(`select c.relname t, a.attname c from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    cross join unnest(con.conkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
    where con.contype = 'p' and con.connamespace = 'public'::regnamespace order by c.relname, k.ord`);
  const schema = {};
  for (const { t, c, d } of columns) (schema[t] ??= { columns: [], key: [] }).columns.push({ name: c, type: d });
  for (const { t, c } of keys) schema[t].key.push(c);
  for (const [t, s] of Object.entries(schema)) if (!SKIP.has(t) && !s.key.length) throw new Error(`geen primaire sleutel: ${t}`);

  const tables = {};
  for (const t of Object.keys(schema).sort()) {
    if (SKIP.has(t)) continue;
    const order = schema[t].key.map((c) => `"${c}"`).join(', ');
    const rows = [];
    for (let offset = 0; ; offset += 1000) {
      const [{ j }] = await pg(`select coalesce(json_agg(x), '[]'::json) j from (select * from public."${t}" order by ${order} limit 1000 offset ${offset}) x`);
      rows.push(...j);
      if (j.length < 1000) break;
    }
    tables[t] = rows;
  }
  const [{ j: users }] = await pg(`select coalesce(json_agg(x), '[]'::json) j from (
    select id, email, encrypted_password, email_confirmed_at, created_at, updated_at,
      raw_user_meta_data ->> 'terms_version' terms_version, raw_user_meta_data ->> 'terms_accepted_at' terms_accepted_at
    from auth.users order by id) x`);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const file = join(dir, 'snapshot.json');
  writeFileSync(file, JSON.stringify({ at: new Date().toISOString(), schema, users, tables }));
  chmodSync(file, 0o600);
  const n = Object.values(tables).reduce((s, r) => s + r.length, 0);
  console.log(`export: ${users.length} accounts, ${n} rijen in ${Object.keys(tables).length} tabellen -> ${file}`);
}

// ── Omzetten ──

/** Postgres-waarde (uit json_agg) -> D1-waarde, volgens het Postgres-type. */
export function toD1(value, type) {
  if (value === null || value === undefined) return null;
  switch (type) {
    case 'boolean':
      return value ? 1 : 0;
    case 'timestamp with time zone': {
      const d = new Date(value);
      if (Number.isNaN(d.getTime())) throw new Error(`geen tijdstip: ${value}`);
      return d.toISOString();
    }
    case 'bigint':
    case 'integer':
    case 'smallint':
    case 'double precision':
      if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`geen getal: ${value}`);
      return value;
    default:
      return String(value);
  }
}

export const lit = (v) => (v === null ? 'NULL' : typeof v === 'number' ? String(v) : `'${String(v).replaceAll("'", "''")}'`);
const ident = (c) => `"${c}"`;

/** De D1-rijen (kolom -> waarde) per tabel, plus server_seq-volgorde voor de synctabellen. */
export function transform(snap) {
  const out = {};
  // Volgorde over alle synctabellen heen zoals in Supabase (server_ts), bij gelijke tijd op tabel en sleutel
  const stamped = [];
  for (const t of Object.keys(snap.tables)) {
    const { columns, key } = snap.schema[t];
    out[t] = snap.tables[t].map((row) => {
      const r = {};
      for (const { name, type } of columns) {
        if (SYNC.includes(t) && name === 'server_ts') continue;
        r[name] = toD1(row[name], type);
      }
      if (SYNC.includes(t)) stamped.push({ t, r, ts: row.server_ts, k: key.map((c) => row[c]).join('\u0000') });
      return r;
    });
  }
  stamped.sort((a, b) => (a.ts < b.ts ? -1 : a.ts > b.ts ? 1 : a.t < b.t ? -1 : a.t > b.t ? 1 : a.k < b.k ? -1 : a.k > b.k ? 1 : 0));
  stamped.forEach((s, i) => (s.r.server_seq = i + 1));
  const users = snap.users.map((u) => ({
    user: {
      id: u.id,
      name: '',
      email: u.email,
      emailVerified: u.email_confirmed_at ? 1 : 0,
      createdAt: toD1(u.created_at, 'timestamp with time zone'),
      updatedAt: toD1(u.updated_at ?? u.created_at, 'timestamp with time zone'),
      termsVersion: u.terms_version ?? null,
      termsAcceptedAt: u.terms_accepted_at ? toD1(u.terms_accepted_at, 'timestamp with time zone') : null,
    },
    // Better Auth: wachtwoord in een "credential"-account; de bcrypt-hash van Supabase blijft (fase 2: verify + rehash)
    account: {
      id: u.id,
      accountId: u.id,
      providerId: 'credential',
      userId: u.id,
      password: u.encrypted_password || null,
      createdAt: toD1(u.created_at, 'timestamp with time zone'),
      updatedAt: toD1(u.updated_at ?? u.created_at, 'timestamp with time zone'),
    },
  }));
  return { tables: out, users, seqCount: stamped.length };
}

function tableOrder(tables) {
  return [...FIRST.filter((t) => t in tables), ...Object.keys(tables).filter((t) => !FIRST.includes(t)).sort()];
}

/** INSERT-opdrachten voor één rij; lange teksten worden er in stukken achteraan geplakt. */
function insertRow(t, r, key, { upsert } = {}) {
  const cols = Object.keys(r);
  const long = cols.filter((c) => typeof r[c] === 'string' && r[c].length > CHUNK);
  const val = (c) => (c === 'server_seq' ? `${r[c]} + (SELECT seq FROM sync_seq)` : long.includes(c) ? "''" : lit(r[c]));
  let sql = `INSERT INTO ${ident(t)} (${cols.map(ident).join(', ')}) VALUES (${cols.map(val).join(', ')})`;
  if (upsert) sql += ` ON CONFLICT (${key.map(ident).join(', ')}) DO UPDATE SET ${cols.filter((c) => !key.includes(c)).map((c) => `${ident(c)} = excluded.${ident(c)}`).join(', ')}`;
  const stmts = [sql + ';'];
  const where = key.map((c) => `${ident(c)} = ${lit(r[c])}`).join(' AND ');
  for (const c of long) {
    for (let i = 0; i < r[c].length; i += CHUNK) {
      stmts.push(`UPDATE ${ident(t)} SET ${ident(c)} = ${ident(c)} || ${lit(r[c].slice(i, i + CHUNK))} WHERE ${where};`);
    }
  }
  return stmts;
}

export function importSql(snap) {
  const { tables, users, seqCount } = transform(snap);
  const order = tableOrder(tables);
  const s = ['-- Gegenereerd door tool/supabase_to_d1.mjs; bevat persoonsgegevens, niet bewaren.', 'UPDATE import_mode SET active = 1;'];
  for (const { user, account } of users) {
    s.push(...insertRow('user', user, ['id'], { upsert: true }));
    s.push(...insertRow('account', account, ['id'], { upsert: true }));
  }
  // Accounts die in Supabase niet meer bestaan (ON DELETE CASCADE ruimt de rest op)
  s.push(`DELETE FROM "user"${users.length ? ` WHERE id NOT IN (${users.map((u) => lit(u.user.id)).join(', ')})` : ''};`);
  for (const t of [...order].reverse()) s.push(`DELETE FROM ${ident(t)};`);
  for (const t of order) for (const r of tables[t]) s.push(...insertRow(t, r, snap.schema[t].key));
  // Nieuwe server_seq's liggen achter alles wat de D1 al uitdeelde (bv. op staging): toestellen missen niets
  s.push(`UPDATE sync_seq SET seq = seq + ${seqCount};`, 'UPDATE import_mode SET active = 0;');
  return s.join('\n') + '\n';
}

// ── D1 (via wrangler) ──

function wrangler(args, opts) {
  // Productie is de bovenste laag van wrangler.jsonc (geen --env)
  const flags = [opts.local ? '--local' : '--remote', ...(opts.env && opts.env !== 'production' ? ['--env', opts.env] : [])];
  return execFileSync('npx', ['wrangler', 'd1', 'execute', 'DB', ...flags, ...args], {
    encoding: 'utf8',
    maxBuffer: 1 << 30,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function d1Query(sql, opts) {
  const res = JSON.parse(wrangler(['--json', '--command', sql], opts));
  return res[0].results;
}

function load(dir, opts) {
  const out = wrangler(['--yes', '--file', join(dir, 'import.sql')], opts);
  console.log(out.trim().split('\n').filter((l) => /executed|rows|error/i.test(l)).join('\n') || 'load: klaar');
}

// ── Vergelijken ──

export function compareRows(snap, d1, { seqBase = 0, seqCount } = {}) {
  const { tables, users, seqCount: imported } = transform(snap);
  seqCount ??= imported;
  const diffs = [];
  // Rijen die na de import op staging veranderden (iemand gebruikte de app intussen): apart, geen fout
  const later = [];
  const since = Date.parse(snap.at);
  const changedSince = (r) =>
    (typeof r.server_seq === 'number' && r.server_seq - seqBase > seqCount) ||
    ['updated_at', 'updatedAt', 'created_at', 'createdAt'].some((c) => typeof r[c] === 'string' && Date.parse(r[c]) > since);
  const perTable = {};
  const keyOf = (r, key) => key.map((c) => r[c]).join('\u0000');
  const check = (t, key, want, got, skip = []) => {
    const g = new Map(got.map((r) => [keyOf(r, key), r]));
    for (const w of want) {
      const k = keyOf(w, key);
      const r = g.get(k);
      if (!r) {
        diffs.push(`${t}: ontbreekt in D1: ${k}`);
        continue;
      }
      g.delete(k);
      if (changedSince(r) && Object.keys(w).some((c) => !skip.includes(c) && w[c] !== (c === 'server_seq' ? r[c] - seqBase : r[c]))) {
        later.push(`${t} ${k}`);
        continue;
      }
      for (const c of Object.keys(w)) {
        if (skip.includes(c)) continue;
        const a = w[c], b = c === 'server_seq' ? r[c] - seqBase : r[c];
        // Wachtwoord-hashes nooit in de uitvoer
        const show = (v) => (c === 'password' ? (v ? '<hash>' : String(v)) : JSON.stringify(v).slice(0, 80));
        if (a !== b) diffs.push(`${t} ${k}: ${c} ${show(a)} != ${show(b)}`);
      }
    }
    for (const [k, r] of g) (changedSince(r) ? later : diffs).push(`${t}: extra in D1: ${k}`);
    perTable[t] = { supabase: want.length, d1: got.length };
  };
  check('user', ['id'], users.map((u) => u.user), d1.user);
  check('account', ['id'], users.map((u) => u.account), d1.account);
  for (const t of Object.keys(tables)) check(t, snap.schema[t].key, tables[t], d1[t] ?? []);
  return { diffs, perTable, later };
}

function compare(dir, opts) {
  const snap = JSON.parse(readFileSync(join(dir, 'snapshot.json'), 'utf8'));
  const d1 = {};
  for (const t of ['user', 'account', ...Object.keys(snap.tables)]) {
    const cols = t === 'user' ? 'id, name, email, emailVerified, createdAt, updatedAt, termsVersion, termsAcceptedAt'
      : t === 'account' ? 'id, accountId, providerId, userId, password, createdAt, updatedAt' : '*';
    d1[t] = d1Query(`SELECT ${cols} FROM "${t}"`, opts);
  }
  // server_seq: de import telt op bij wat er al was; de laagste geïmporteerde waarde is base + 1
  const seqs = SYNC.flatMap((t) => (d1[t] ?? []).map((r) => r.server_seq));
  const seqBase = seqs.length ? Math.min(...seqs) - 1 : 0;
  const { diffs, perTable, later } = compareRows(snap, d1, { seqBase });
  const [{ active }] = d1Query('SELECT active FROM import_mode', opts);
  if (active !== 0) diffs.push('import_mode staat nog aan');
  // Per gebruiker: aantallen (alleen tabellen met user_id)
  const perUser = {};
  for (const t of Object.keys(snap.tables)) {
    if (!snap.schema[t].columns.some((c) => c.name === 'user_id')) continue;
    for (const r of snap.tables[t]) (perUser[r.user_id] ??= { s: 0, d: 0 }).s++;
    for (const r of d1[t]) (perUser[r.user_id] ??= { s: 0, d: 0 }).d++;
  }
  const userDiffs = Object.entries(perUser).filter(([, v]) => v.s !== v.d);
  for (const [t, v] of Object.entries(perTable)) console.log(`${t.padEnd(18)} supabase ${String(v.supabase).padStart(6)}  d1 ${String(v.d1).padStart(6)}`);
  console.log(`gebruikers met afwijkende aantallen: ${userDiffs.length} (van ${Object.keys(perUser).length})`);
  if (later.length) console.log(`na de import gewijzigd op staging (geen fout): ${later.length}${later.length <= 5 ? ` (${later.join(', ')})` : ''}`);
  console.log(`verschillen: ${diffs.length}`);
  for (const d of diffs.slice(0, 50)) console.log('  ' + d);
  return diffs.length + userDiffs.length;
}

// ── Opdrachtregel ──

if (import.meta.url === `file://${process.argv[1]}`) {
  const [cmd, dir, ...rest] = process.argv.slice(2);
  const opts = { local: rest.includes('--local'), env: rest.includes('--env') ? rest[rest.indexOf('--env') + 1] : undefined };
  if (!cmd || !dir) {
    console.error('Gebruik: supabase_to_d1.mjs export|sql|load|compare|all <map> [--env staging] [--local]');
    process.exit(2);
  }
  const sql = () => {
    const file = join(dir, 'import.sql');
    writeFileSync(file, importSql(JSON.parse(readFileSync(join(dir, 'snapshot.json'), 'utf8'))));
    chmodSync(file, 0o600);
    console.log(`sql: ${file}`);
  };
  if (cmd === 'export' || cmd === 'all') await exportSnapshot(dir);
  if (cmd === 'sql' || cmd === 'all') sql();
  if (cmd === 'load' || cmd === 'all') load(dir, opts);
  if (cmd === 'compare' || cmd === 'all') process.exitCode = compare(dir, opts) ? 1 : 0;
}
