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
if ! command -v readelf >/dev/null 2>&1; then
  echo "readelf is required to compute the OCCT runtime dependency closure." >&2
  exit 5
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "GH_TOKEN is required to resolve workflow artifacts." >&2
  exit 6
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
  exit 7
fi

tar -xzf "$TARBALL" -C "$SDK_ROOT"

CONFIG="$(find "$SDK_ROOT" -type f -name OpenCASCADEConfig.cmake -print -quit)"
if [[ -z "$CONFIG" ]]; then
  echo "OpenCASCADEConfig.cmake missing from staged SDK." >&2
  exit 8
fi

declare -A SDK_LIBS=()
while IFS= read -r -d '' library; do
  SDK_LIBS["$(basename "$library")"]="$library"
done < <(find "$SDK_ROOT" -type f -name '*.so' -print0)

if [[ ${#SDK_LIBS[@]} -eq 0 ]]; then
  echo "No OCCT shared libraries found in staged SDK." >&2
  exit 9
fi

# These are the only OCCT toolkit roots directly used by the STEP/XCAF importer.
# The rest of the runtime set is derived from ELF DT_NEEDED entries below.
ROOT_LIBS=(
  libTKDESTEP.so
  libTKXCAF.so
  libTKMesh.so
)

QUEUE=("${ROOT_LIBS[@]}")
declare -A STAGED=()
queue_index=0
while (( queue_index < ${#QUEUE[@]} )); do
  name="${QUEUE[$queue_index]}"
  queue_index=$((queue_index + 1))

  if [[ -n "${STAGED[$name]:-}" ]]; then
    continue
  fi

  library="${SDK_LIBS[$name]:-}"
  if [[ -z "$library" ]]; then
    echo "Required OCCT runtime library missing from SDK: $name" >&2
    exit 10
  fi

  cp -f "$library" "$JNI_ROOT/$name"
  STAGED[$name]=1

  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue
    # Android system libraries and libc++ are supplied outside the OCCT SDK.
    # Only recurse into dependencies that are actually shipped by this SDK.
    if [[ -n "${SDK_LIBS[$dependency]:-}" && -z "${STAGED[$dependency]:-}" ]]; then
      QUEUE+=("$dependency")
    fi
  done < <(
    readelf -d "$library" \
      | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'
  )
done

SO_COUNT=${#STAGED[@]}
printf '%s\n' "${!STAGED[@]}" | sort > "$DOWNLOAD_ROOT/occt-runtime-libs.txt"

# CMake discovers its config recursively from this root.
echo "BREPSIGHT_OCCT_ROOT=$SDK_ROOT" >> "${GITHUB_ENV:?GITHUB_ENV is required in CI}"
echo "BREPSIGHT_OCCT_ENABLED=true" >> "$GITHUB_ENV"
echo "BREPSIGHT_OCCT_RUN_ID=$RUN_ID" >> "$GITHUB_ENV"
echo "BREPSIGHT_OCCT_SO_COUNT=$SO_COUNT" >> "$GITHUB_ENV"

echo "Staged $SO_COUNT OCCT shared libraries for $ABI from ELF dependency closure"
echo "OCCT SDK root: $SDK_ROOT"
echo "Runtime manifest: $DOWNLOAD_ROOT/occt-runtime-libs.txt"
