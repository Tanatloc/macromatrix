// Belastingtest (fase 6): N nagebootste gebruikers tegelijk tegen staging, zoals de app bij het openen en loggen:
// 20 regels versturen, de 9 tabellen tegelijk ophalen, my_pro en friend_me. Meet de duur per soort verzoek.
// Testgebruikers en sessies worden rechtstreeks in D1 gezet (geen registratielimiet) en daarna weer gewist.
//   node tool/load_check.mjs https://api-staging.macromatrix.eu --env staging [--users 500]
import { randomBytes } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { DOMAIN, base, rest, run, sql } from './checklib.mjs';

const N = Number(rest.includes('--users') ? rest[rest.indexOf('--users') + 1] : 500);
// --rate R: R gebruikers per seconde laten beginnen (aanhoudende stroom) in plaats van allemaal tegelijk
const RATE = rest.includes('--rate') ? Number(rest[rest.indexOf('--rate') + 1]) : 0;
const flags = [rest.includes('--local') ? '--local' : '--remote', '--env', 'staging'];
const TABLES = ['settings', 'foods', 'diary', 'meals', 'biometrics', 'notes', 'exercise', 'fasts', 'repeats'];
const now = new Date();
const users = Array.from({ length: N }, (_, i) => ({ id: crypto.randomUUID(), email: `load${i}-${run}@${DOMAIN}`, token: randomBytes(24).toString('hex') }));

// Gebruikers en sessies in één SQL-bestand
const exp = new Date(now.getTime() + 86_400_000).toISOString();
const t = now.toISOString();
const lines = users.flatMap((u) => [
  `INSERT INTO "user" (id, name, email, "emailVerified", "createdAt", "updatedAt") VALUES ('${u.id}', '', '${u.email}', 1, '${t}', '${t}');`,
  `INSERT INTO session (id, "expiresAt", token, "createdAt", "updatedAt", "userId") VALUES ('${u.id}', '${exp}', '${u.token}', '${t}', '${t}', '${u.id}');`,
]);
const file = `${tmpdir()}/load-${run}.sql`;
writeFileSync(file, lines.join('\n') + '\n', { mode: 0o600 });

const times = {};
let errors = 0;
const errorKinds = {};
async function timed(kind, url, init) {
  const t0 = performance.now();
  try {
    const r = await fetch(url, init);
    await r.arrayBuffer();
    const db = /db;dur=([\d.]+)/.exec(r.headers.get('server-timing') ?? '')?.[1];
    if (db) (times[`  waarvan D1 (${kind})`] ??= []).push(Number(db));
    if (!r.ok) {
      errors++;
      errorKinds[`${kind} ${r.status}`] = (errorKinds[`${kind} ${r.status}`] ?? 0) + 1;
    }
  } catch (e) {
    errors++;
    errorKinds[`${kind} ${e.cause?.code ?? e.message}`] = (errorKinds[`${kind} ${e.cause?.code ?? e.message}`] ?? 0) + 1;
  }
  (times[kind] ??= []).push(performance.now() - t0);
}

async function session(u) {
  const h = { authorization: `Bearer ${u.token}`, 'content-type': 'application/json' };
  const day = now.toISOString().slice(0, 10);
  const rows = Array.from({ length: 20 }, (_, i) => ({
    id: `${u.id}-${i}`, day, meal: i % 4, food_ref: 'ciqual:13005', name: 'Banana, raw', grams: 100 + i, quantity: 1,
    nutrients: JSON.stringify({ energy: 90, protein: 1.1, carbs: 20 }), created_at: Date.now(), updated_at: Date.now(), deleted: 0,
  }));
  await timed('push (20 regels)', `${base}/v1/sync/push`, { method: 'POST', headers: h, body: JSON.stringify({ table: 'diary', rows }) });
  await timed('pull-all (9 tabellen)', `${base}/v1/sync/pull-all`, { method: 'POST', headers: h, body: JSON.stringify({ cursors: Object.fromEntries(TABLES.map((tb) => [tb, '0'])), limit: 500 }) });
  await timed('rpc my_pro', `${base}/v1/rpc/my_pro`, { method: 'POST', headers: h, body: '{}' });
  await timed('rpc friend_me', `${base}/v1/rpc/friend_me`, { method: 'POST', headers: h, body: JSON.stringify({ p_name: null, p_avatar: null, p_level: 1 }) });
}

const pct = (a, p) => a[Math.min(a.length - 1, Math.floor((p / 100) * a.length))];
try {
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'DB', ...flags, '--yes', '--file', file], { stdio: ['ignore', 'pipe', 'pipe'] });
  // Elke sessie één keer gebruiken (Better Auth verlengt een nieuwe sessie dan meteen): zoals in het echt, waar dat
  // hoogstens één keer per dag per toestel gebeurt. Met 10 tegelijk, en niet meegeteld.
  for (let i = 0; i < users.length; i += 10) {
    await Promise.all(users.slice(i, i + 10).map((u) => fetch(`${base}/v1/rpc/my_pro`, { method: 'POST', headers: { authorization: `Bearer ${u.token}`, 'content-type': 'application/json' }, body: '{}' }).then((r) => r.arrayBuffer())));
  }
  console.log(`${N} testgebruikers aangemaakt en opgewarmd; ${RATE ? `${RATE} per seconde` : 'allemaal tegelijk'}`);
  const t0 = performance.now();
  await Promise.all(users.map((u, i) => (RATE ? new Promise((ok) => setTimeout(ok, (i * 1000) / RATE)).then(() => session(u)) : session(u))));
  const total = (performance.now() - t0) / 1000;
  console.log(`klaar in ${total.toFixed(1)} s, ${Object.values(times).flat().length} verzoeken, fouten: ${errors}${errors ? ` ${JSON.stringify(errorKinds)}` : ''}`);
  console.log('soort                 aantal   p50    p95    p99   (ms)');
  const all = [];
  for (const [k, a] of Object.entries(times)) {
    a.sort((x, y) => x - y);
    all.push(...a);
    console.log(`${k.padEnd(20)} ${String(a.length).padStart(6)} ${pct(a, 50).toFixed(0).padStart(5)} ${pct(a, 95).toFixed(0).padStart(6)} ${pct(a, 99).toFixed(0).padStart(6)}`);
  }
  all.sort((x, y) => x - y);
  console.log(`${'alles'.padEnd(20)} ${String(all.length).padStart(6)} ${pct(all, 50).toFixed(0).padStart(5)} ${pct(all, 95).toFixed(0).padStart(6)} ${pct(all, 99).toFixed(0).padStart(6)}`);
} finally {
  sql(`DELETE FROM "user" WHERE email LIKE 'load%-${run}@${DOMAIN}'`);
  execFileSync('rm', ['-f', file]);
}
process.exit(0);
