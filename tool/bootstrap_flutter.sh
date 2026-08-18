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

# `flutter create` generates the stock counter-app widget test when the Android
# scaffold is missing. BrepSight has its own committed tests, so remove only
# that recognizable template test instead of letting it reference `MyApp`.
if [[ -f test/widget_test.dart ]] && grep -q "MyApp" test/widget_test.dart; then
  rm test/widget_test.dart
fi

# cad_engine uses native C++ and currently requires API 24. The release APK is
# deliberately arm64-only. `--target-platform android-arm64` controls Flutter's
# target, but plugin AARs may still contribute prebuilt jniLibs for other ABIs.
# Constrain native compilation with abiFilters *and* final AAR/JNI packaging so
# third-party plugin payload cannot silently re-introduce 32-bit libraries.
if [[ -f android/app/build.gradle.kts ]]; then
  sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 24/' android/app/build.gradle.kts
  python3 - <<'PY'
from pathlib import Path
path = Path('android/app/build.gradle.kts')
text = path.read_text()
if 'abiFilters' not in text:
    needle = '        minSdk = 24\n'
    if needle not in text:
        raise SystemExit('Unable to locate Kotlin DSL minSdk insertion point.')
    text = text.replace(
        needle,
        needle + '        ndk {\n            abiFilters += listOf("arm64-v8a")\n        }\n',
        1,
    )
if 'brepsight arm64-only packaging' not in text:
    marker = '\n    buildTypes {'
    if marker not in text:
        raise SystemExit('Unable to locate Kotlin DSL packaging insertion point.')
    packaging = '''

    // brepsight arm64-only packaging: plugin AARs may contain prebuilt JNI
    // libraries for every ABI even when the app target is android-arm64.
    packaging {
        jniLibs {
            excludes += setOf(
                "**/armeabi/**",
                "**/armeabi-v7a/**",
                "**/x86/**",
                "**/x86_64/**",
            )
        }
    }
'''
    text = text.replace(marker, packaging + marker, 1)
path.write_text(text)
PY
elif [[ -f android/app/build.gradle ]]; then
  sed -i 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 24/' android/app/build.gradle
  python3 - <<'PY'
from pathlib import Path
path = Path('android/app/build.gradle')
text = path.read_text()
if 'abiFilters' not in text:
    needle = '        minSdkVersion 24\n'
    if needle not in text:
        raise SystemExit('Unable to locate Groovy minSdk insertion point.')
    text = text.replace(
        needle,
        needle + "        ndk {\n            abiFilters 'arm64-v8a'\n        }\n",
        1,
    )
if 'brepsight arm64-only packaging' not in text:
    marker = '\n    buildTypes {'
    if marker not in text:
        raise SystemExit('Unable to locate Groovy packaging insertion point.')
    packaging = '''

    // brepsight arm64-only packaging: remove plugin AAR JNI for other ABIs.
    packagingOptions {
        jniLibs {
            excludes += ['**/armeabi/**', '**/armeabi-v7a/**', '**/x86/**', '**/x86_64/**']
        }
    }
'''
    text = text.replace(marker, packaging + marker, 1)
path.write_text(text)
PY
fi

if ! grep -Eq 'abiFilters.*arm64-v8a' android/app/build.gradle.kts android/app/build.gradle 2>/dev/null; then
  echo 'Android scaffold did not retain the arm64-v8a ABI filter.' >&2
  exit 3
fi
if ! grep -Eq 'armeabi-v7a' android/app/build.gradle.kts android/app/build.gradle 2>/dev/null; then
  echo 'Android scaffold did not retain non-arm64 JNI packaging exclusions.' >&2
  exit 4
fi

flutter pub get
flutter analyze

echo 'BrepSight source tree is ready. Build an installable Android APK with:'
echo '  flutter build apk --debug --target-platform android-arm64'
