#!/usr/bin/env bash
set -euo pipefail

LIB3MF_TAG="${LIB3MF_TAG:-v2.5.0}"
LIB3MF_COMMIT="${LIB3MF_COMMIT:-64bb454d1fcb53effa57d3cef752a10d740d41a2}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-24}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/.build/lib3mf-android}"
INSTALL_ROOT="${INSTALL_ROOT:-$PWD/.build/lib3mf-sdk/${ANDROID_ABI}}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point to an Android NDK installation}"
TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
if [[ ! -f "$TOOLCHAIN" ]]; then
  echo "Android NDK toolchain not found: $TOOLCHAIN" >&2
  exit 2
fi

SRC="$BUILD_ROOT/src"
BUILD="$BUILD_ROOT/build"
rm -rf "$BUILD" "$INSTALL_ROOT"
mkdir -p "$BUILD_ROOT" "$INSTALL_ROOT"

if [[ ! -d "$SRC/.git" ]]; then
  rm -rf "$SRC"
  git clone --filter=blob:none --no-checkout https://github.com/3MFConsortium/lib3mf.git "$SRC"
fi

git -C "$SRC" fetch --depth=1 origin "$LIB3MF_COMMIT"
git -C "$SRC" checkout --detach "$LIB3MF_COMMIT"
git -C "$SRC" submodule sync --recursive
git -C "$SRC" submodule update --init --recursive --depth=1

ACTUAL_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$LIB3MF_COMMIT" ]]; then
  echo "lib3mf source mismatch: expected $LIB3MF_COMMIT, got $ACTUAL_COMMIT" >&2
  exit 3
fi

cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ANDROID_ABI" \
  -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_ROOT" \
  -DLIB3MF_BUILD_SHARED=ON \
  -DUSE_INCLUDED_ZLIB=ON \
  -DUSE_INCLUDED_LIBZIP=ON \
  -DUSE_INCLUDED_SSL=ON \
  -DUSE_INCLUDED_CPPBASE64=ON \
  -DUSE_INCLUDED_FASTFLOAT=ON \
  -DSTRIP_BINARIES=ON

cmake --build "$BUILD" --parallel "$JOBS"
cmake --install "$BUILD"

cat > "$INSTALL_ROOT/brepsight-lib3mf-sdk.json" <<EOF
{
  "lib3mfTag": "$LIB3MF_TAG",
  "lib3mfCommit": "$LIB3MF_COMMIT",
  "androidAbi": "$ANDROID_ABI",
  "androidPlatform": "$ANDROID_PLATFORM",
  "libraryType": "shared",
  "cppStandard": "C++17",
  "purpose": "BrepSight 3MF import/export SDK"
}
EOF

find "$INSTALL_ROOT" -type f \( -name 'lib3mf.so' -o -name 'lib3mf.so.*' -o -name 'lib3mf*.so' \) -print -quit | grep -q .
find "$INSTALL_ROOT" -type f -name 'lib3mf_implicit.hpp' -o -name 'lib3mf_dynamic.hpp' -o -name 'lib3mf.hpp' | grep -q . || \
  find "$INSTALL_ROOT" -type f -path '*/Bindings/Cpp/*' -print -quit | grep -q .

echo "lib3mf Android SDK ready at: $INSTALL_ROOT"
