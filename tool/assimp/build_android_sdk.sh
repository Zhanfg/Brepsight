#!/usr/bin/env bash
set -euo pipefail

ASSIMP_TAG="${ASSIMP_TAG:-v6.0.5}"
ASSIMP_COMMIT="${ASSIMP_COMMIT:-392a658f9c271be965271f45e7521a1b80ea4392}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-24}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/.build/assimp-android}"
INSTALL_ROOT="${INSTALL_ROOT:-$PWD/.build/assimp-sdk/${ANDROID_ABI}}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
LOG_ROOT="${LOG_ROOT:-$BUILD_ROOT/logs}"
CURRENT_STAGE="bootstrap"

mkdir -p "$LOG_ROOT"

on_error() {
  local code=$?
  echo "::error title=Assimp Android SDK failed::stage=${CURRENT_STAGE}; exit=${code}; line=${BASH_LINENO[0]}" >&2
  for log in "$LOG_ROOT/configure.log" "$LOG_ROOT/build.log" "$LOG_ROOT/install.log"; do
    if [[ -f "$log" ]]; then
      echo "===== tail: $(basename "$log") =====" >&2
      tail -n 180 "$log" >&2 || true
    fi
  done
  if [[ -d "$INSTALL_ROOT" ]]; then
    echo "===== partial install inventory =====" >&2
    find "$INSTALL_ROOT" -maxdepth 6 -type f | sort | tail -n 160 >&2 || true
  fi
  exit "$code"
}
trap on_error ERR

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point to an Android NDK installation}"
TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
if [[ ! -f "$TOOLCHAIN" ]]; then
  echo "Android NDK toolchain not found: $TOOLCHAIN" >&2
  exit 2
fi

SRC="$BUILD_ROOT/src"
BUILD="$BUILD_ROOT/build"
rm -rf "$BUILD" "$INSTALL_ROOT"
mkdir -p "$BUILD_ROOT" "$INSTALL_ROOT" "$LOG_ROOT"

CURRENT_STAGE="source"
if [[ ! -d "$SRC/.git" ]]; then
  rm -rf "$SRC"
  git clone --filter=blob:none --no-checkout https://github.com/assimp/assimp.git "$SRC"
fi

git -C "$SRC" fetch --depth=1 origin "$ASSIMP_COMMIT"
git -C "$SRC" checkout --detach "$ASSIMP_COMMIT"
ACTUAL_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$ASSIMP_COMMIT" ]]; then
  echo "Assimp source mismatch: expected $ASSIMP_COMMIT, got $ACTUAL_COMMIT" >&2
  exit 3
fi

CURRENT_STAGE="configure"
echo "Configuring Assimp $ASSIMP_TAG ($ASSIMP_COMMIT) for $ANDROID_ABI / $ANDROID_PLATFORM"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ANDROID_ABI" \
  -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_ROOT" \
  -DCMAKE_PLATFORM_NO_VERSIONED_SONAME=ON \
  -DBUILD_SHARED_LIBS=ON \
  -DASSIMP_BUILD_TESTS=OFF \
  -DASSIMP_BUILD_ASSIMP_TOOLS=OFF \
  -DASSIMP_BUILD_SAMPLES=OFF \
  -DASSIMP_BUILD_DOCS=OFF \
  -DASSIMP_NO_EXPORT=ON \
  -DASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT=OFF \
  -DASSIMP_BUILD_FBX_IMPORTER=ON \
  -DASSIMP_BUILD_COLLADA_IMPORTER=ON \
  -DASSIMP_BUILD_PLY_IMPORTER=ON \
  -DASSIMP_BUILD_OFF_IMPORTER=ON \
  -DASSIMP_BUILD_USD_IMPORTER=OFF \
  -DASSIMP_BUILD_M3D_IMPORTER=OFF \
  -DASSIMP_BUILD_VRML_IMPORTER=OFF \
  -DASSIMP_BUILD_DRACO=OFF \
  -DASSIMP_BUILD_ZLIB=ON \
  -DASSIMP_WARNINGS_AS_ERRORS=OFF \
  -DASSIMP_INJECT_DEBUG_POSTFIX=OFF \
  -DASSIMP_IGNORE_GIT_HASH=ON \
  2>&1 | tee "$LOG_ROOT/configure.log"

CURRENT_STAGE="build"
echo "Building Assimp with $JOBS jobs"
cmake --build "$BUILD" --target assimp --parallel "$JOBS" 2>&1 | tee "$LOG_ROOT/build.log"

CURRENT_STAGE="install"
echo "Installing Assimp to $INSTALL_ROOT"
cmake --install "$BUILD" 2>&1 | tee "$LOG_ROOT/install.log"

CURRENT_STAGE="verify"
cat > "$INSTALL_ROOT/brepsight-assimp-sdk.json" <<EOF
{
  "assimpTag": "$ASSIMP_TAG",
  "assimpCommit": "$ASSIMP_COMMIT",
  "androidAbi": "$ANDROID_ABI",
  "androidPlatform": "$ANDROID_PLATFORM",
  "libraryType": "shared",
  "soname": "libassimp.so",
  "enabledImporters": ["FBX", "COLLADA", "PLY", "OFF"],
  "usdImporter": false,
  "blendPolicy": "not-enabled-by-brepsight",
  "purpose": "BrepSight DCC mesh import SDK"
}
EOF

LIBRARY="$INSTALL_ROOT/lib/libassimp.so"
CONFIG="$(find "$INSTALL_ROOT" -type f -name 'assimpConfig.cmake' -print -quit)"
HEADER="$INSTALL_ROOT/include/assimp/Importer.hpp"
if [[ ! -f "$LIBRARY" || -z "$CONFIG" || ! -f "$HEADER" ]]; then
  echo "Installed Assimp SDK is incomplete." >&2
  echo "library=$LIBRARY" >&2
  echo "config=$CONFIG" >&2
  echo "header=$HEADER" >&2
  false
fi

SONAME="$(readelf -d "$LIBRARY" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p' | head -n1)"
if [[ "$SONAME" != "libassimp.so" ]]; then
  echo "Unexpected Assimp Android SONAME: '${SONAME:-<missing>}'" >&2
  false
fi

trap - ERR
echo "Verified library: $LIBRARY"
echo "Verified SONAME: $SONAME"
echo "Verified config: $CONFIG"
echo "Verified header: $HEADER"
echo "Assimp Android SDK ready at: $INSTALL_ROOT"
