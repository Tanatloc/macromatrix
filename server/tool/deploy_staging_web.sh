#!/bin/bash
# Staging-site bouwen en uitrollen: site/ + de webapp (API_URL = staging-server) in build/staging-site, dan de Worker
# macromatrix-staging-web (server/web). Nodig: flutter in PATH, CLOUDFLARE_API_TOKEN met Workers-rechten.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=build/staging-site
rm -rf "$out"
flutter build web --release --no-web-resources-cdn --base-href /app/ --dart-define-from-file=supabase.json \
  --dart-define=API_URL=https://api-staging.macromatrix.eu -o "$out/app"
cp -r site/. "$out/"
# Testomgeving: niet in zoekmachines
printf '/*\n  X-Robots-Tag: noindex\n' >> "$out/_headers"
# Zoals tool/build_site.sh: de voedingsdatabase gecomprimeerd en in stukken (bestanden hoogstens 25 MiB)
db=$out/app/assets/assets/db/foods.db
gzip -9 -n -c "$db" > "$db.gz"
split -b 20M -d -a 1 "$db" "$db."
ls "$db".[0-9] | wc -l | tr -d ' ' > "$db.parts"
rm "$db"
cd server/web && npx wrangler deploy
