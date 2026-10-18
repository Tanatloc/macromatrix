#!/bin/bash
# Nieuwe Android-release op GitHub (Tanatloc/macromatrix-releases) voor Obtainium.
# Gebruik: tool/release.sh "Wat er nieuw is"   (versie komt uit pubspec.yaml; verhoog die eerst)
# Vereist de releasesleutel in ~/.config/macromatrix/key.properties.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f ~/.config/macromatrix/key.properties ] || { echo "Releasesleutel ontbreekt"; exit 1; }
v=$(grep '^version:' pubspec.yaml | sed 's/version: //; s/+.*//')
flutter build apk --release --dart-define-from-file=supabase.json
cp build/app/outputs/flutter-apk/app-release.apk "/tmp/MacroMatrix-$v-universal.apk"
flutter build apk --release --split-per-abi --target-platform android-arm64,android-arm --dart-define-from-file=supabase.json
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "/tmp/MacroMatrix-$v-arm64-v8a.apk"
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "/tmp/MacroMatrix-$v-armeabi-v7a.apk"
gh release create "v$v" "/tmp/MacroMatrix-$v-arm64-v8a.apk" "/tmp/MacroMatrix-$v-armeabi-v7a.apk" "/tmp/MacroMatrix-$v-universal.apk" \
  -R Tanatloc/macromatrix-releases --title "MacroMatrix $v" --notes "${1:-Bug fixes and improvements.}"
