#!/bin/bash
# De bestaande releasesleutel versleuteld exporteren voor Play App Signing, zodat de Play-versie dezelfde handtekening
# houdt als de APK's op GitHub (gebruikers kunnen dan wisselen zonder opnieuw te installeren).
# Gebruik: tool/play_export_key.sh <encryptiesleutel.pem>
#   De encryptiesleutel krijg je in de Play Console: App-integriteit → App-ondertekening → "Sleutel exporteren en
#   uploaden vanuit Java-keystore" → "Download de openbare sleutel van de encryptie". Wachtwoorden komen uit
#   ~/.config/macromatrix/key.properties en worden nergens getoond. Uitvoer: ~/.config/macromatrix/pepk/encrypted_private_key.zip
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -eq 1 ] && [ -f "$1" ] || { echo "Gebruik: $0 <encryptiesleutel.pem uit de Play Console>"; exit 1; }
props=~/.config/macromatrix/key.properties
jar=~/.config/macromatrix/pepk/pepk.jar
[ -f "$props" ] || { echo "Releasesleutel ontbreekt ($props)"; exit 1; }
[ -f "$jar" ] || { mkdir -p "$(dirname "$jar")"; curl -sL -o "$jar" https://www.gstatic.com/play-apps-publisher-rapid/signing-tool/prod/pepk.jar; }
get() { grep "^$1=" "$props" | cut -d= -f2-; }
store=$(get storeFile); case "$store" in /*) ;; *) store="android/app/$store" ;; esac
out=~/.config/macromatrix/pepk/encrypted_private_key.zip
java -jar "$jar" --keystore="$store" --alias="$(get keyAlias)" --output="$out" \
  --include-cert --rsa-aes-encryption --encryption-key-path="$1" \
  --keystore-pass="$(get storePassword)" --key-pass="$(get keyPassword)"
chmod 600 "$out"
echo "Klaar: $out (upload dit bestand in de Play Console)"
