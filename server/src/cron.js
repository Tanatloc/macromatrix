// Opruimen, elke nacht (Cron Trigger). Was pg_cron in Supabase (niet-bevestigde accounts na 30 dagen), plus wat
// Better Auth en de limieten laten liggen.
const DAY = 86_400_000;

export async function cleanup(db, now = new Date()) {
  const iso = (ms) => new Date(now.getTime() - ms).toISOString();
  const res = await db.batch([
    // Nooit bevestigd en ouder dan 30 dagen (ON DELETE CASCADE ruimt de rest op)
    db.prepare('DELETE FROM "user" WHERE "emailVerified" = 0 AND "createdAt" < ?').bind(iso(30 * DAY)),
    db.prepare('DELETE FROM session WHERE "expiresAt" < ?').bind(now.toISOString()),
    db.prepare('DELETE FROM verification WHERE "expiresAt" < ?').bind(now.toISOString()),
    db.prepare('DELETE FROM "rateLimit" WHERE "lastRequest" < ?').bind(now.getTime() - DAY),
    db.prepare('DELETE FROM signup_ips WHERE at < ?').bind(iso(DAY)),
    db.prepare('DELETE FROM test_outbox WHERE at < ?').bind(iso(DAY)),
  ]);
  const [users, sessions, codes, limits, ips, outbox] = res.map((r) => r.meta?.changes ?? 0);
  return { users, sessions, codes, limits, ips, outbox };
}
