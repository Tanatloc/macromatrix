#!/bin/bash
# Website (homepage, privacy, voorwaarden uit site/) en de webversie van de app onder /app/ samen in build/site.
# Gebruik: tool/build_site.sh   (daarna build/site uploaden; zie README)
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn --base-href /app/ --dart-define-from-file=supabase.json
rm -rf build/site
cp -r site build/site
cp -r build/web build/site/app
echo "Klaar: build/site (homepage op /, app op /app/)"
