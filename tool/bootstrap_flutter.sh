#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter SDK is required.' >&2
  exit 2
fi

flutter --version

if [[ ! -d android/app ]]; then
  echo 'Generating the Android application scaffold for BrepSight...'
  flutter create --platforms=android --org dev.brepsight --project-name brepsight .
fi

flutter pub get
flutter analyze

echo 'BrepSight source tree is ready. Build Android with:'
echo '  flutter build apk --debug'
