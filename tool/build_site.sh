#!/bin/bash
# Website (homepage, privacy, voorwaarden uit site/) en de webversie van de app onder /app/ samen in build/site.
# Gebruik: tool/build_site.sh   (daarna build/site uploaden; zie README)
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn --base-href /app/ --dart-define-from-file=supabase.json
rm -rf build/site
cp -r site build/site
# Dezelfde homepage zonder downloadknoppen op /about/: daar linkt de Android-app naar ("Meer over de app"). Een app
# uit Google Play mag niet naar een APK buiten de Play Store wijzen (GP-18). Alles tussen <!--dl--> en <!--/dl-->
# in site/index.html valt weg (test/social_r11_test.dart controleert dat er geen downloadlink buiten staat).
mkdir -p build/site/about
# Links naar de homepage blijven op /about/, anders staat de APK-download weer één tik verder
perl -0pe 's/<!--dl-->.*?<!--\/dl-->//gs; s{href="/"}{href="/about/"}g; s{href="/#}{href="/about/#}g' site/index.html > build/site/about/index.html
cp -r build/web build/site/app
# Cloudflare Pages neemt geen bestanden boven 25 MiB: de voedingsdatabase in stukken van 20 MiB (de webapp plakt ze
# weer aan elkaar, zie lib/platform/platform_web.dart)
db=build/site/app/assets/assets/db/foods.db
# Gecomprimeerd (± 7 MB in plaats van 46): dat haalt de webapp eerst; de stukken blijven voor oude browsers
gzip -9 -n -c "$db" > "$db.gz"
split -b 20M -d -a 1 "$db" "$db."
ls "$db".[0-9] | wc -l | tr -d ' ' > "$db.parts"
rm "$db"
echo "Klaar: build/site (homepage op /, app op /app/)"
