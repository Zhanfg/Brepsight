#!/usr/bin/env bash
set -euo pipefail

LIB3MF_TAG="${LIB3MF_TAG:-v2.5.0}"
LIB3MF_COMMIT="${LIB3MF_COMMIT:-64bb454d1fcb53effa57d3cef752a10d740d41a2}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-24}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/.build/lib3mf-android}"
INSTALL_ROOT="${INSTALL_ROOT:-$PWD/.build/lib3mf-sdk/${ANDROID_ABI}}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
LOG_ROOT="${LOG_ROOT:-$BUILD_ROOT/logs}"
CURRENT_STAGE="bootstrap"

mkdir -p "$LOG_ROOT"

on_error() {
  local code=$?
  echo "::error title=lib3mf Android SDK failed::stage=${CURRENT_STAGE}; exit=${code}; line=${BASH_LINENO[0]}" >&2
  for log in "$LOG_ROOT/configure.log" "$LOG_ROOT/build.log" "$LOG_ROOT/install.log"; do
    if [[ -f "$log" ]]; then
      echo "===== tail: $(basename "$log") =====" >&2
      tail -n 160 "$log" >&2 || true
    fi
  done
  if [[ -d "$INSTALL_ROOT" ]]; then
    echo "===== partial install inventory =====" >&2
    find "$INSTALL_ROOT" -maxdepth 5 -type f | sort | tail -n 120 >&2 || true
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

CURRENT_STAGE="configure"
echo "Configuring lib3mf $LIB3MF_TAG ($LIB3MF_COMMIT) for $ANDROID_ABI / $ANDROID_PLATFORM"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ANDROID_ABI" \
  -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_ROOT" \
  -DLIB3MF_BUILD_SHARED=ON \
  -DLIB3MF_TESTS=OFF \
  -DUSE_INCLUDED_ZLIB=ON \
  -DUSE_INCLUDED_LIBZIP=ON \
  -DUSE_INCLUDED_SSL=ON \
  -DUSE_INCLUDED_CPPBASE64=ON \
  -DUSE_INCLUDED_FASTFLOAT=ON \
  -DSTRIP_BINARIES=ON \
  2>&1 | tee "$LOG_ROOT/configure.log"

CURRENT_STAGE="build"
echo "Building lib3mf with $JOBS jobs"
cmake --build "$BUILD" --target lib3mf --parallel "$JOBS" 2>&1 | tee "$LOG_ROOT/build.log"

CURRENT_STAGE="install"
echo "Installing lib3mf to $INSTALL_ROOT"
cmake --install "$BUILD" 2>&1 | tee "$LOG_ROOT/install.log"

CURRENT_STAGE="verify"
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

LIBRARY="$(find "$INSTALL_ROOT" -type f \( -name 'lib3mf.so' -o -name 'lib3mf.so.*' -o -name 'lib3mf*.so' \) -print -quit)"
if [[ -z "$LIBRARY" ]]; then
  echo "No installed lib3mf shared library found." >&2
  false
fi

BINDING="$(find "$INSTALL_ROOT" -type f \( -name 'lib3mf_implicit.hpp' -o -name 'lib3mf_dynamic.hpp' -o -name 'lib3mf.hpp' \) -print -quit)"
if [[ -z "$BINDING" ]]; then
  BINDING="$(find "$INSTALL_ROOT" -type f -path '*/Bindings/Cpp/*' -print -quit)"
fi
if [[ -z "$BINDING" ]]; then
  echo "No installed lib3mf C++ binding header found." >&2
  false
fi

trap - ERR
echo "Verified library: $LIBRARY"
echo "Verified C++ binding: $BINDING"
echo "lib3mf Android SDK ready at: $INSTALL_ROOT"
