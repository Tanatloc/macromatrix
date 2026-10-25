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
