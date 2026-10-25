// Synchroniseren (zelfde rol als PostgREST op de negen synctabellen in Supabase):
// - pull: rijen van jou met server_seq na een cursor, oplopend;
// - push: upsert van jouw rijen; geeft per sleutel de updated_at terug van wat echt opgeslagen werd (een oudere
//   versie laat de trigger vallen, de klok kan begrensd zijn); met insertOnly blijft een bestaande rij staan;
// - fetch: de huidige rijen voor een lijst sleutels.
// user_id komt altijd uit de sessie, nooit uit de rij. server_seq zet alleen de trigger.
import { DbError, fromD1 } from './errors.js';

export const SYNC_TABLES = {
  settings: 'key',
  foods: 'id',
  diary: 'id',
  meals: 'id',
  biometrics: 'id',
  notes: 'day',
  exercise: 'id',
  fasts: 'id',
  repeats: 'id',
};

const MAX_ROWS = 500;
const q = (c) => `"${c}"`;

/** Kolommen en types per tabel, uit het schema zelf (één keer per isolate). */
const columnCache = new Map();
async function columns(db, table) {
  if (!columnCache.has(table)) {
    const { results } = await db.prepare(`PRAGMA table_info(${q(table)})`).all();
    columnCache.set(table, new Map(results.map((c) => [c.name, String(c.type).toUpperCase()])));
  }
  return columnCache.get(table);
}

function tableOf(name) {
  const key = SYNC_TABLES[name];
  if (!key) throw new DbError('42P01', `relation "${name}" does not exist`, { status: 404 });
  return key;
}

/** Een rij van de app nakijken: alleen bekende kolommen, met het juiste type (Postgres weigerde dat ook). */
function clean(row, cols, table) {
  if (!row || typeof row !== 'object' || Array.isArray(row)) throw new DbError('22P02', 'invalid row');
  const out = {};
  for (const [c, v] of Object.entries(row)) {
    if (c === 'user_id' || c === 'server_seq' || c === 'server_ts') continue;
    const type = cols.get(c);
    if (!type) throw new DbError('PGRST204', `Could not find the '${c}' column of '${table}'`);
    if (v === null) {
      out[c] = null;
    } else if (type === 'INTEGER') {
      if (typeof v === 'boolean') out[c] = v ? 1 : 0;
      else if (Number.isInteger(v)) out[c] = v;
      else throw new DbError('22P02', `invalid input syntax for type integer: "${v}"`);
    } else if (type === 'REAL') {
      if (typeof v !== 'number' || !Number.isFinite(v)) throw new DbError('22P02', `invalid input syntax for type double precision: "${v}"`);
      out[c] = v;
    } else {
      if (typeof v !== 'string') throw new DbError('22P02', `invalid input for text column ${c}`);
      out[c] = v;
    }
  }
  return out;
}

export async function pull(db, uid, table, since, limit) {
  tableOf(table);
  const n = Math.min(Math.max(Number.parseInt(limit, 10) || MAX_ROWS, 1), 1000);
  const after = Number.parseInt(since ?? '0', 10) || 0;
  const { results } = await db
    .prepare(`SELECT * FROM ${q(table)} WHERE user_id = ? AND server_seq > ? ORDER BY server_seq LIMIT ?`)
    .bind(uid, after, n)
    .all();
  return results;
}

export async function fetchRows(db, uid, table, keys) {
  const key = tableOf(table);
  if (!Array.isArray(keys) || keys.some((k) => typeof k !== 'string')) throw new DbError('22P02', 'keys must be strings');
  const out = [];
  for (let i = 0; i < keys.length; i += 90) {
    const part = keys.slice(i, i + 90);
    if (!part.length) break;
    const { results } = await db
      .prepare(`SELECT * FROM ${q(table)} WHERE user_id = ? AND ${q(key)} IN (${part.map(() => '?').join(',')})`)
      .bind(uid, ...part)
      .all();
    out.push(...results);
  }
  return out;
}

/** Geeft { sleutel: updated_at } van de rijen die echt opgeslagen werden. */
export async function push(db, uid, table, rows, { insertOnly = false } = {}) {
  const key = tableOf(table);
  if (!Array.isArray(rows)) throw new DbError('22P02', 'rows must be a list');
  if (rows.length > MAX_ROWS) throw new DbError('54000', `at most ${MAX_ROWS} rows per request`);
  if (!rows.length) return {};
  const cols = await columns(db, table);
  const clean_ = rows.map((r) => clean(r, cols, table));
  const keys = [];
  const stmts = clean_.map((r) => {
    if (typeof r[key] !== 'string' || !r[key]) throw new DbError('23502', `null value in column "${key}"`);
    keys.push(r[key]);
    const names = Object.keys(r);
    const set = names.filter((c) => c !== key).map((c) => `${q(c)} = excluded.${q(c)}`);
    const action = insertOnly || !set.length ? 'NOTHING' : `UPDATE SET ${set.join(', ')}`;
    return db
      .prepare(
        `INSERT INTO ${q(table)} (user_id, ${names.map(q).join(', ')}) VALUES (?, ${names.map(() => '?').join(', ')})
         ON CONFLICT (user_id, ${q(key)}) DO ${action} RETURNING ${q(key)} AS k`,
      )
      .bind(uid, ...names.map((c) => r[c]));
  });
  // In dezelfde batch (= transactie): de stand na het opslaan, met de begrensde klok
  const readers = [];
  for (let i = 0; i < keys.length; i += 90) {
    const part = keys.slice(i, i + 90);
    readers.push(db.prepare(`SELECT ${q(key)} AS k, updated_at FROM ${q(table)} WHERE user_id = ? AND ${q(key)} IN (${part.map(() => '?').join(',')})`).bind(uid, ...part));
  }
  let res;
  try {
    res = await db.batch([...stmts, ...readers]);
  } catch (e) {
    throw fromD1(e);
  }
  const stored = new Set(res.slice(0, stmts.length).flatMap((r) => r.results.map((x) => String(x.k))));
  const out = {};
  for (const r of res.slice(stmts.length)) for (const x of r.results) if (stored.has(String(x.k))) out[x.k] = x.updated_at;
  return out;
}
