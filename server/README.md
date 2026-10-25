# MacroMatrix server (Cloudflare)

Worker `macromatrix-api` with D1, replacing the Supabase backend. Work in progress: only the database schema and
the data import exist so far.

- `migrations/`: D1 schema (SQLite). `0001_init.sql` holds every table from `../supabase/migrations`, the Better Auth
  core tables and the sync triggers (`server_seq` instead of `server_ts`; older versions ignored; clock capped at
  now + 5 min; row limits per user).
- `tool/supabase_to_d1.mjs`: copies all data from Supabase into a D1 and compares it row by row.
- `tool/d1_check.mjs`: checks the sync triggers on a real D1.
- `test/`: `npm test` (node:sqlite, Node 22.5 or newer).

```sh
npm ci --ignore-scripts
npx wrangler d1 migrations apply DB --env staging --local
node tool/supabase_to_d1.mjs all <private dir> --env staging --local
```

## Backups and recovery

- **Every night (02:30 UTC)** the Worker writes the whole database, gzipped and encrypted with AES-256-GCM
  (`BACKUP_KEY`), to R2: `daily/YYYY-MM-DD.mmb` plus a manifest (`.json`: row count and hash per table). R2 deletes
  them after 30 days (the privacy policy promises that). Sessions, codes and rate limits are not included.
- **Every month (1st, 04:00 UTC)** the latest backup is restored into a separate D1 (`RESTORE_DB`) and compared
  with its manifest; the result goes to `checks/` and a failure mails `ADMIN_EMAIL`.
- **Weekly** a machine outside Cloudflare copies the backups with rclone (read-only R2 key for that bucket).
- **Quick undo** of a mistake in the last 30 days: D1 Time Travel,
  `wrangler d1 time-travel restore DB --env <env> --timestamp <ISO time>` (or `--bookmark`).
- **Full recovery from a backup file**, also without Cloudflare:
  `node tool/backup_restore.mjs <file.mmb> --key-file <file with BACKUP_KEY=…> --sql restore.sql`
  restores into a local SQLite database, checks it against the manifest, and writes SQL for a new D1:
  `wrangler d1 migrations apply <db> --remote` then `wrangler d1 execute <db> --remote --file restore.sql`.
- Without `BACKUP_KEY` a backup cannot be read: keep a copy of the key outside Cloudflare.
