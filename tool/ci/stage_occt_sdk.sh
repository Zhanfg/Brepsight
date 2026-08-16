#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-Zhanfg/Brepsight}"
WORKFLOW="${OCCT_WORKFLOW:-occt-android-sdk.yml}"
ARTIFACT="${OCCT_ARTIFACT:-occt-V8_0_0-arm64-v8a}"
ABI="${ANDROID_ABI:-arm64-v8a}"
DOWNLOAD_ROOT="${1:-$PWD/.build/occt-consume}"
SDK_ROOT="$DOWNLOAD_ROOT/sdk"
JNI_ROOT="$PWD/packages/cad_engine/android/src/main/jniLibs/$ABI"

rm -rf "$DOWNLOAD_ROOT" "$JNI_ROOT"
mkdir -p "$DOWNLOAD_ROOT" "$SDK_ROOT" "$JNI_ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is not installed; OCCT SDK staging skipped." >&2
  exit 4
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "GH_TOKEN is required to resolve workflow artifacts." >&2
  exit 5
fi

RUN_ID="$(
  gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --status success \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty'
)"

if [[ -z "$RUN_ID" ]]; then
  echo "No successful $WORKFLOW run exists yet; building mesh-only APK."
  echo "BREPSIGHT_OCCT_ENABLED=false" >> "${GITHUB_ENV:?GITHUB_ENV is required in CI}"
  echo "BREPSIGHT_OCCT_RUN_ID=" >> "$GITHUB_ENV"
  exit 0
fi

echo "Using OCCT SDK workflow run: $RUN_ID"
gh run download "$RUN_ID" \
  --repo "$REPO" \
  --name "$ARTIFACT" \
  --dir "$DOWNLOAD_ROOT/artifact"

TARBALL="$(find "$DOWNLOAD_ROOT/artifact" -maxdepth 2 -type f -name 'occt-*.tar.gz' -print -quit)"
if [[ -z "$TARBALL" ]]; then
  echo "OCCT SDK artifact did not contain an SDK tarball." >&2
  exit 6
fi

tar -xzf "$TARBALL" -C "$SDK_ROOT"

CONFIG="$(find "$SDK_ROOT" -type f -name OpenCASCADEConfig.cmake -print -quit)"
if [[ -z "$CONFIG" ]]; then
  echo "OpenCASCADEConfig.cmake missing from staged SDK." >&2
  exit 7
fi

SO_COUNT=0
while IFS= read -r -d '' library; do
  cp -f "$library" "$JNI_ROOT/$(basename "$library")"
  SO_COUNT=$((SO_COUNT + 1))
done < <(find "$SDK_ROOT" -type f -name '*.so' -print0)

if [[ "$SO_COUNT" -eq 0 ]]; then
  echo "No OCCT shared libraries found in staged SDK." >&2
  exit 8
fi

# CMake discovers its config recursively from this root.
echo "BREPSIGHT_OCCT_ROOT=$SDK_ROOT" >> "${GITHUB_ENV:?GITHUB_ENV is required in CI}"
echo "BREPSIGHT_OCCT_ENABLED=true" >> "$GITHUB_ENV"
echo "BREPSIGHT_OCCT_RUN_ID=$RUN_ID" >> "$GITHUB_ENV"

echo "Staged $SO_COUNT OCCT shared libraries for $ABI"
echo "OCCT SDK root: $SDK_ROOT"
