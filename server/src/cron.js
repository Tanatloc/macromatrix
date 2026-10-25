// Geplande taken (Cron Triggers): elke nacht opruimen (was pg_cron in Supabase: niet-bevestigde accounts na 30
// dagen, plus wat Better Auth en de limieten laten liggen) en een back-up; elke maand een hersteltest.
import { makeBackup, putStream, restoreBackup, verifyRestore } from './backup.js';
import { sendAlert } from './mail.js';

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

// ── Back-ups (src/backup.js) ──


const day = (now) => now.toISOString().slice(0, 10);

/** Elke nacht: de hele database versleuteld naar R2 (daily/…); op de 1e van de maand ook monthly/…. */
export async function dailyBackup(env, now = new Date()) {
  const key = `daily/${day(now)}.mmb`;
  try {
    const { stream, manifest } = await makeBackup(env.DB, env.BACKUP_KEY, now);
    await putStream(env.BACKUP, key, stream);
    const rows = Object.values(manifest.tables).reduce((n, t) => n + t.rows, 0);
    await env.BACKUP.put(`${key}.json`, JSON.stringify(manifest), { httpMetadata: { contentType: 'application/json' } });
    if (now.getUTCDate() === 1) {
      const obj = await env.BACKUP.get(key);
      await env.BACKUP.put(`monthly/${day(now).slice(0, 7)}.mmb`, obj.body);
    }
    console.log(`back-up ${key}: ${rows} rijen in ${Object.keys(manifest.tables).length} tabellen`);
    return { key, rows };
  } catch (e) {
    await sendAlert(env, 'Back-up mislukt', `${key}\n${e?.stack ?? e}`).catch(() => {});
    throw e;
  }
}

/**
 * Elke maand: de nieuwste back-up terugzetten in de testdatabase (RESTORE_DB) en vergelijken met zijn manifest.
 * Een back-up telt pas als hij terug te zetten is.
 */
export async function restoreCheck(env, now = new Date()) {
  try {
    const list = await env.BACKUP.list({ prefix: 'daily/' });
    const latest = list.objects.filter((o) => o.key.endsWith('.mmb')).sort((a, b) => (a.key < b.key ? 1 : -1))[0];
    if (!latest) throw new Error('geen back-up gevonden');
    const file = await (await env.BACKUP.get(latest.key)).arrayBuffer();
    const manifest = await restoreBackup(env.RESTORE_DB, file, env.BACKUP_KEY);
    const diffs = await verifyRestore(env.RESTORE_DB, manifest);
    const result = { at: now.toISOString(), backup: latest.key, ok: diffs.length === 0, diffs };
    await env.BACKUP.put(`checks/${day(now)}.json`, JSON.stringify(result));
    if (diffs.length) await sendAlert(env, 'Hersteltest: verschillen', `${latest.key}\n${diffs.join('\n')}`);
    console.log(`hersteltest ${latest.key}: ${diffs.length ? diffs.join('; ') : 'ok'}`);
    return result;
  } catch (e) {
    await sendAlert(env, 'Hersteltest mislukt', String(e?.stack ?? e)).catch(() => {});
    throw e;
  }
}
