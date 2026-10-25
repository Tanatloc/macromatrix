// Een back-up (.mmb) terugzetten zonder Cloudflare: alleen het bestand en de sleutel (BACKUP_KEY).
//   node tool/backup_restore.mjs <bestand.mmb> --key-file <bestand met BACKUP_KEY=…> [--sql uit.sql] [--sqlite uit.db]
// Zet de back-up altijd eerst terug in een SQLite-database met het juiste schema en controleert die tegen het
// manifest (0 verschillen). --sql schrijft daarnaast INSERT-opdrachten om in een nieuwe D1 te laden
// (na `wrangler d1 migrations apply`): `wrangler d1 execute <db> --remote --file uit.sql`.
// --sqlite bewaart de teruggezette database als bestand.
import { readFileSync, writeFileSync } from 'node:fs';
import { readBackup, restoreBackup, verifyRestore } from '../src/backup.js';
import { d1 } from '../test/d1.mjs';

const [file, ...rest] = process.argv.slice(2);
const opt = (name) => (rest.includes(name) ? rest[rest.indexOf(name) + 1] : null);
if (!file || !opt('--key-file')) {
  console.error('Gebruik: backup_restore.mjs <bestand.mmb> --key-file <bestand> [--sql uit.sql] [--sqlite uit.db]');
  process.exit(2);
}
const key = readFileSync(opt('--key-file'), 'utf8').match(/BACKUP_KEY=(\S+)/)?.[1];
if (!key) throw new Error('geen BACKUP_KEY in het sleutelbestand');
const bytes = new Uint8Array(readFileSync(file));

const db = d1();
const manifest = await restoreBackup(db, bytes, key);
const diffs = await verifyRestore(db, manifest);
const rows = Object.values(manifest.tables).reduce((n, t) => n + t.rows, 0);
console.log(`back-up van ${manifest.at}: ${rows} rijen in ${Object.keys(manifest.tables).length} tabellen`);
console.log(diffs.length ? `VERSCHILLEN:\n  ${diffs.join('\n  ')}` : 'teruggezet en gecontroleerd: 0 verschillen met het manifest');

if (opt('--sql')) {
  const lit = (v) => (v === null ? 'NULL' : typeof v === 'number' ? String(v) : `'${String(v).replaceAll("'", "''")}'`);
  const out = ['UPDATE import_mode SET active = 1;'];
  for await (const line of readBackup(bytes, key)) {
    if (line.manifest) continue;
    const cols = Object.keys(line.r);
    if (line.t === 'sync_seq') out.push(`UPDATE sync_seq SET seq = ${lit(line.r.seq)} WHERE id = ${lit(line.r.id)};`);
    else out.push(`INSERT INTO "${line.t}" (${cols.map((c) => `"${c}"`).join(', ')}) VALUES (${cols.map((c) => lit(line.r[c])).join(', ')});`);
  }
  out.push('UPDATE import_mode SET active = 0;');
  writeFileSync(opt('--sql'), out.join('\n') + '\n', { mode: 0o600 });
  console.log(`SQL: ${opt('--sql')}`);
}
if (opt('--sqlite')) {
  db.raw.exec(`VACUUM INTO '${opt('--sqlite').replaceAll("'", "''")}'`);
  console.log(`SQLite: ${opt('--sqlite')}`);
}
process.exit(diffs.length ? 1 : 0);
