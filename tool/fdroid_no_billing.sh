#!/bin/bash
# Voor de F-Droid-build (prebuild in fdroid/online.divinenet.macromatrix.yml): Google Play Billing eruit halen.
# De Play Billing-bibliotheek (com.android.billingclient) is niet vrij. We halen in_app_purchase uit pubspec.yaml en
# vervangen lib/sync/play_store_plugin.dart door de stub zonder winkel; Pro toont dan "Binnenkort", zoals op het web.
set -euo pipefail
cd "$(dirname "$0")/.."
sed -i '/^  in_app_purchase\(_android\)\?:/d' pubspec.yaml
cp lib/sync/play_store_stub.dart lib/sync/play_store_plugin.dart
if grep -q '^  in_app_purchase' pubspec.yaml || grep -q 'package:in_app_purchase' lib/sync/play_store_plugin.dart; then
  echo "in_app_purchase zit er nog in"
  exit 1
fi
echo "Google Play Billing verwijderd"
