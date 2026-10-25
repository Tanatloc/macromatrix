// Fouten met dezelfde codes als Postgres/PostgREST, zodat de app (PostgrestException.code) ze herkent zoals bij
// Supabase: 22… ongeldige waarde, 23… regel geschonden, 54… te veel rijen, P0001 een eigen melding (raise exception),
// 42501 geen toegang, PGRST202 onbekende functie, PGRST301 niet ingelogd.

export class DbError extends Error {
  constructor(code, message, { status = 400, details = null, hint = null } = {}) {
    super(message);
    this.code = code;
    this.status = status;
    this.details = details;
    this.hint = hint;
  }

  toJSON() {
    return { code: this.code, message: this.message, details: this.details, hint: this.hint };
  }
}

/** Zoals `raise exception '…'` in plpgsql (SQLSTATE P0001, of een andere [code]). */
export const raise = (message, code = 'P0001') => {
  throw new DbError(code, message);
};

/** Een fout van D1 (SQLite) omzetten naar de Postgres-code die Supabase in dat geval gaf. */
export function fromD1(e) {
  if (e instanceof DbError) return e;
  const m = String(e?.message ?? e);
  const pick = (code, status = 400) => new DbError(code, m.replace(/^D1_ERROR:\s*/, '').replace(/: SQLITE_[A-Z_]+$/, ''), { status });
  if (/te veel rijen/.test(m)) return pick('54000');
  if (/user_id kan niet wijzigen/.test(m)) return pick('42501', 403);
  if (/CHECK constraint failed/i.test(m)) return pick('23514');
  if (/NOT NULL constraint failed/i.test(m)) return pick('23502');
  if (/UNIQUE constraint failed|PRIMARY KEY/i.test(m)) return pick('23505');
  if (/FOREIGN KEY constraint failed/i.test(m)) return pick('23503');
  if (/datatype mismatch|too big|string or blob too big/i.test(m)) return pick('22001');
  if (/no such column|has no column named/i.test(m)) return pick('42703');
  console.error('D1-fout', m);
  return new DbError('XX000', 'Internal error', { status: 500 });
}

export const json = (body, status = 200, headers = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', ...headers } });

export const errorResponse = (e) => {
  const err = fromD1(e);
  return json(err.toJSON(), err.status);
};
