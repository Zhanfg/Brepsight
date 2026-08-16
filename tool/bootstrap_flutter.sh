#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter SDK is required.' >&2
  exit 2
fi

flutter --version

if [[ ! -d android/app ]]; then
  echo 'Generating the Android application scaffold for BrepSight...'
  # --org dev + project-name brepsight => Android applicationId dev.brepsight.
  flutter create --platforms=android --org dev --project-name brepsight .
fi

# cad_engine uses native C++ and currently requires API 24. Keep the generated
# application scaffold aligned even if Flutter's template default changes.
if [[ -f android/app/build.gradle.kts ]]; then
  sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 24/' android/app/build.gradle.kts
elif [[ -f android/app/build.gradle ]]; then
  sed -i 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 24/' android/app/build.gradle
fi

flutter pub get
flutter analyze

echo 'BrepSight source tree is ready. Build an installable Android APK with:'
echo '  flutter build apk --debug'
