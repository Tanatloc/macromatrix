#!/bin/bash
# Test-app voor de proefperiode: zelfde app, maar praat met de staging-server en heet "MM Staging" (eigen app-id
# online.divinenet.macromatrix.staging, staat naast de gewone app). Daarna op de staging-site gezet:
# https://staging.macromatrix.eu/download/macromatrix-staging.apk
set -euo pipefail
cd "$(dirname "$0")/../.."
flutter build apk --release --dart-define-from-file=supabase.json --dart-define=API_URL=https://api-staging.macromatrix.eu \
  --android-project-arg=staging=true --split-per-abi --target-platform android-arm64
mkdir -p build/staging-site/download
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk build/staging-site/download/macromatrix-staging.apk
echo "APK: build/staging-site/download/macromatrix-staging.apk (uitrollen met server/tool/deploy_staging_web.sh of wrangler deploy in server/web)"
