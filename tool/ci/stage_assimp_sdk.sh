#!/usr/bin/env bash
set -euo pipefail

ASSIMP_TAG="${ASSIMP_TAG:-v6.0.5}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
WORKFLOW="assimp-android-sdk.yml"
ARTIFACT="assimp-${ASSIMP_TAG}-${ANDROID_ABI}"
STAGE_ROOT="$PWD/.build/assimp-consume"
SDK_ROOT="$STAGE_ROOT/sdk"
JNI_ROOT="$PWD/packages/cad_engine/android/src/main/jniLibs/${ANDROID_ABI}"

rm -rf "$STAGE_ROOT"
mkdir -p "$SDK_ROOT" "$JNI_ROOT"
rm -f "$JNI_ROOT/libassimp.so"

export BREPSIGHT_ASSIMP_ENABLED=false
export BREPSIGHT_ASSIMP_ROOT=""
export BREPSIGHT_ASSIMP_RUN_ID=""

write_disabled() {
  {
    echo 'BREPSIGHT_ASSIMP_ENABLED=false'
    echo 'BREPSIGHT_ASSIMP_ROOT='
    echo 'BREPSIGHT_ASSIMP_RUN_ID='
  } >> "$GITHUB_ENV"
}

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo 'GH_TOKEN is unavailable; continuing without Assimp.'
  write_disabled
  exit 0
fi

SOURCE_BRANCH="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-main}}"
find_run() {
  local branch="$1"
  gh run list \
    --repo "$GITHUB_REPOSITORY" \
    --workflow "$WORKFLOW" \
    --branch "$branch" \
    --status success \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty'
}

RUN_ID="$(find_run "$SOURCE_BRANCH")"
if [[ -z "$RUN_ID" && "$SOURCE_BRANCH" != "main" ]]; then
  RUN_ID="$(find_run main)"
fi

if [[ -z "$RUN_ID" ]]; then
  echo "No successful Assimp SDK artifact found for ${SOURCE_BRANCH} or main; continuing without DCC provider."
  write_disabled
  exit 0
fi

mkdir -p "$STAGE_ROOT/artifact"
gh run download "$RUN_ID" \
  --repo "$GITHUB_REPOSITORY" \
  --name "$ARTIFACT" \
  --dir "$STAGE_ROOT/artifact"

TARBALL="$(find "$STAGE_ROOT/artifact" -type f -name 'assimp-*.tar.gz' -print -quit)"
if [[ -z "$TARBALL" ]]; then
  echo "Artifact $ARTIFACT from run $RUN_ID does not contain an SDK tarball." >&2
  exit 2
fi

tar -xzf "$TARBALL" -C "$SDK_ROOT"
CONFIG="$(find "$SDK_ROOT" -type f -name 'assimpConfig.cmake' -print -quit)"
LIBRARY="$SDK_ROOT/lib/libassimp.so"
HEADER="$SDK_ROOT/include/assimp/Importer.hpp"
METADATA="$SDK_ROOT/brepsight-assimp-sdk.json"
if [[ -z "$CONFIG" || ! -f "$LIBRARY" || ! -f "$HEADER" || ! -f "$METADATA" ]]; then
  echo "Staged Assimp SDK is incomplete: $SDK_ROOT" >&2
  exit 3
fi

if ! grep -q '392a658f9c271be965271f45e7521a1b80ea4392' "$METADATA"; then
  echo 'Staged Assimp SDK commit identity does not match the BrepSight pin.' >&2
  exit 4
fi
SONAME="$(readelf -d "$LIBRARY" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p' | head -n1)"
if [[ "$SONAME" != 'libassimp.so' ]]; then
  echo "Staged Assimp SDK has unexpected SONAME: '${SONAME:-<missing>}'" >&2
  exit 5
fi

cp "$LIBRARY" "$JNI_ROOT/libassimp.so"

export BREPSIGHT_ASSIMP_ENABLED=true
export BREPSIGHT_ASSIMP_ROOT="$SDK_ROOT"
export BREPSIGHT_ASSIMP_RUN_ID="$RUN_ID"
{
  echo 'BREPSIGHT_ASSIMP_ENABLED=true'
  echo "BREPSIGHT_ASSIMP_ROOT=$SDK_ROOT"
  echo "BREPSIGHT_ASSIMP_RUN_ID=$RUN_ID"
} >> "$GITHUB_ENV"

echo "Staged Assimp SDK from run $RUN_ID: $SDK_ROOT"
