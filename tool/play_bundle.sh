#!/bin/bash
# App bundle (.aab) voor Google Play. Gebruik: tool/play_bundle.sh   (versie komt uit pubspec.yaml; verhoog die eerst)
# Vereist de releasesleutel in ~/.config/macromatrix/key.properties: die wordt de uploadsleutel bij Play App Signing.
# Uploaden doe je zelf in de Play Console (Testen of Productie, Nieuwe release).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f ~/.config/macromatrix/key.properties ] || { echo "Releasesleutel ontbreekt"; exit 1; }
[ -f supabase.json ] || { echo "supabase.json ontbreekt"; exit 1; }
v=$(grep '^version:' pubspec.yaml | sed 's/version: //; s/+.*//')
flutter build appbundle --release --dart-define-from-file=supabase.json
cp build/app/outputs/bundle/release/app-release.aab "/tmp/MacroMatrix-$v.aab"
echo "Klaar: /tmp/MacroMatrix-$v.aab"
