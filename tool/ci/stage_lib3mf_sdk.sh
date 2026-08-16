#!/usr/bin/env bash
set -euo pipefail

LIB3MF_TAG="${LIB3MF_TAG:-v2.5.0}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
WORKFLOW="lib3mf-android-sdk.yml"
ARTIFACT="lib3mf-${LIB3MF_TAG}-${ANDROID_ABI}"
STAGE_ROOT="$PWD/.build/lib3mf-consume"
SDK_ROOT="$STAGE_ROOT/sdk"
JNI_ROOT="$PWD/packages/cad_engine/android/src/main/jniLibs/${ANDROID_ABI}"

rm -rf "$STAGE_ROOT"
mkdir -p "$SDK_ROOT" "$JNI_ROOT"
rm -f "$JNI_ROOT/lib3mf.so"

export BREPSIGHT_LIB3MF_ENABLED=false
export BREPSIGHT_LIB3MF_ROOT=""
export BREPSIGHT_LIB3MF_RUN_ID=""

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo 'GH_TOKEN is unavailable; continuing without lib3mf.'
  {
    echo 'BREPSIGHT_LIB3MF_ENABLED=false'
    echo 'BREPSIGHT_LIB3MF_ROOT='
    echo 'BREPSIGHT_LIB3MF_RUN_ID='
  } >> "$GITHUB_ENV"
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
  echo "No successful lib3mf SDK artifact found for ${SOURCE_BRANCH} or main; continuing without 3MF."
  {
    echo 'BREPSIGHT_LIB3MF_ENABLED=false'
    echo 'BREPSIGHT_LIB3MF_ROOT='
    echo 'BREPSIGHT_LIB3MF_RUN_ID='
  } >> "$GITHUB_ENV"
  exit 0
fi

mkdir -p "$STAGE_ROOT/artifact"
gh run download "$RUN_ID" \
  --repo "$GITHUB_REPOSITORY" \
  --name "$ARTIFACT" \
  --dir "$STAGE_ROOT/artifact"

TARBALL="$(find "$STAGE_ROOT/artifact" -type f -name 'lib3mf-*.tar.gz' -print -quit)"
if [[ -z "$TARBALL" ]]; then
  echo "Artifact $ARTIFACT from run $RUN_ID does not contain an SDK tarball." >&2
  exit 2
fi

tar -xzf "$TARBALL" -C "$SDK_ROOT"
CONFIG="$SDK_ROOT/lib/cmake/lib3mf/lib3mfConfig.cmake"
LIBRARY="$SDK_ROOT/lib/lib3mf.so"
if [[ ! -f "$CONFIG" || ! -f "$LIBRARY" ]]; then
  echo "Staged lib3mf SDK is incomplete: $SDK_ROOT" >&2
  exit 3
fi

cp "$LIBRARY" "$JNI_ROOT/lib3mf.so"

export BREPSIGHT_LIB3MF_ENABLED=true
export BREPSIGHT_LIB3MF_ROOT="$SDK_ROOT"
export BREPSIGHT_LIB3MF_RUN_ID="$RUN_ID"
{
  echo 'BREPSIGHT_LIB3MF_ENABLED=true'
  echo "BREPSIGHT_LIB3MF_ROOT=$SDK_ROOT"
  echo "BREPSIGHT_LIB3MF_RUN_ID=$RUN_ID"
} >> "$GITHUB_ENV"

echo "Staged lib3mf SDK from run $RUN_ID: $SDK_ROOT"
