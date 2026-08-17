#!/usr/bin/env bash
set -euo pipefail

ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
WORKFLOW="opennurbs-android-sdk.yml"
ARTIFACT="opennurbs-8.x-${ANDROID_ABI}"
STAGE_ROOT="$PWD/.build/opennurbs-consume"
SDK_ROOT="$STAGE_ROOT/sdk"
JNI_ROOT="$PWD/packages/cad_engine/android/src/main/jniLibs/${ANDROID_ABI}"
PIN="00bdd2ce8f3e4cd3d4921343909bbe123b2e9d58"

rm -rf "$STAGE_ROOT"
mkdir -p "$SDK_ROOT" "$JNI_ROOT"
rm -f "$JNI_ROOT/libOpenNURBS.so"

write_disabled() {
  {
    echo 'BREPSIGHT_OPENNURBS_ENABLED=false'
    echo 'BREPSIGHT_OPENNURBS_ROOT='
    echo 'BREPSIGHT_OPENNURBS_RUN_ID='
  } >> "$GITHUB_ENV"
}

if [[ -z "${GH_TOKEN:-}" ]]; then
  write_disabled
  exit 0
fi

SOURCE_BRANCH="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-main}}"
find_run() {
  gh run list --repo "$GITHUB_REPOSITORY" --workflow "$WORKFLOW" --branch "$1" \
    --status success --limit 1 --json databaseId --jq '.[0].databaseId // empty'
}
RUN_ID="$(find_run "$SOURCE_BRANCH")"
if [[ -z "$RUN_ID" && "$SOURCE_BRANCH" != main ]]; then RUN_ID="$(find_run main)"; fi
if [[ -z "$RUN_ID" ]]; then
  echo 'No successful openNURBS SDK artifact is available yet; continuing without 3DM provider.'
  write_disabled
  exit 0
fi

mkdir -p "$STAGE_ROOT/artifact"
gh run download "$RUN_ID" --repo "$GITHUB_REPOSITORY" --name "$ARTIFACT" --dir "$STAGE_ROOT/artifact"
TARBALL="$(find "$STAGE_ROOT/artifact" -name 'opennurbs-*.tar.gz' -print -quit)"
[[ -n "$TARBALL" ]] || { echo 'openNURBS artifact has no SDK tarball.' >&2; exit 2; }
tar -xzf "$TARBALL" -C "$SDK_ROOT"
LIB="$SDK_ROOT/lib/libOpenNURBS.so"
HEADER="$SDK_ROOT/include/opennurbs_public.h"
META="$SDK_ROOT/brepsight-opennurbs-sdk.json"
[[ -f "$LIB" && -f "$HEADER" && -f "$META" ]] || { echo 'Staged openNURBS SDK is incomplete.' >&2; exit 3; }
grep -q "$PIN" "$META" || { echo 'Staged openNURBS identity does not match pin.' >&2; exit 4; }
cp "$LIB" "$JNI_ROOT/libOpenNURBS.so"
{
  echo 'BREPSIGHT_OPENNURBS_ENABLED=true'
  echo "BREPSIGHT_OPENNURBS_ROOT=$SDK_ROOT"
  echo "BREPSIGHT_OPENNURBS_RUN_ID=$RUN_ID"
} >> "$GITHUB_ENV"
echo "Staged openNURBS SDK from run $RUN_ID"
