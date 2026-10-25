// D1 nagebootst met node:sqlite, voor tests: prepare/bind/first/all/run/raw en batch (als één transactie), met de
// migraties al uitgevoerd. Foutmeldingen zoals D1 ze geeft ("D1_ERROR: …").
import { readFileSync, readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

const dir = new URL('../migrations/', import.meta.url);

class Statement {
  constructor(db, sql, params = []) {
    this.db = db;
    this.sql = sql;
    this.params = params;
  }
  bind(...params) {
    return new Statement(this.db, this.sql, params.map((p) => (p === undefined ? null : typeof p === 'boolean' ? (p ? 1 : 0) : p)));
  }
  _run(mode) {
    try {
      const st = this.db.prepare(this.sql);
      if (mode === 'run' && !/\breturning\b/i.test(this.sql)) {
        const r = st.run(...this.params);
        return { results: [], success: true, meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } };
      }
      const rows = st.all(...this.params).map((r) => ({ ...r }));
      return { results: rows, success: true, meta: { changes: rows.length } };
    } catch (e) {
      throw new Error(`D1_ERROR: ${e.message}: SQLITE_ERROR`);
    }
  }
  async all() {
    return this._run('all');
  }
  async run() {
    return this._run('run');
  }
  async first(col) {
    const r = this._run('all').results[0] ?? null;
    return col === undefined ? r : (r?.[col] ?? null);
  }
  async raw() {
    return this._run('all').results.map((r) => Object.values(r));
  }
}

export function d1() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) db.exec(readFileSync(new URL(f, dir), 'utf8'));
  return {
    raw: db,
    prepare: (sql) => new Statement(db, sql),
    async batch(stmts) {
      db.exec('BEGIN');
      try {
        const out = stmts.map((s) => s._run('all'));
        db.exec('COMMIT');
        return out;
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
    },
    async exec(sql) {
      db.exec(sql);
      return { count: 1 };
    },
  };
}

/** Een gebruiker aanmaken zoals Better Auth het doet. */
export function addUser(db, id, email = `${id}@example.com`) {
  const now = new Date().toISOString();
  db.raw.prepare('INSERT INTO "user" (id, name, email, emailVerified, createdAt, updatedAt) VALUES (?, ?, ?, 1, ?, ?)').run(id, '', email, now, now);
  return id;
}
