#!/bin/bash
# Website (homepage, privacy, voorwaarden uit site/) en de webversie van de app onder /app/ samen in build/site.
# Gebruik: tool/build_site.sh   (daarna build/site uploaden; zie README)
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn --base-href /app/ --dart-define-from-file=supabase.json
rm -rf build/site
cp -r site build/site
cp -r build/web build/site/app
# Cloudflare Pages neemt geen bestanden boven 25 MiB: de voedingsdatabase in stukken van 20 MiB (de webapp plakt ze
# weer aan elkaar, zie lib/platform/platform_web.dart)
db=build/site/app/assets/assets/db/foods.db
split -b 20M -d -a 1 "$db" "$db."
ls "$db".[0-9] | wc -l | tr -d ' ' > "$db.parts"
rm "$db"
echo "Klaar: build/site (homepage op /, app op /app/)"
