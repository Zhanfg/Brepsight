#!/usr/bin/env bash
set -euo pipefail

OCCT_TAG="${OCCT_TAG:-V8_0_0}"
OCCT_COMMIT="${OCCT_COMMIT:-d3056ef80c9668f395da40f5fd7be186cae4501f}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-24}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/.build/occt-android}"
INSTALL_ROOT="${INSTALL_ROOT:-$PWD/.build/occt-sdk/${ANDROID_ABI}}"
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
  git clone --filter=blob:none --no-checkout https://github.com/Open-Cascade-SAS/OCCT.git "$SRC"
fi

git -C "$SRC" fetch --depth=1 origin "$OCCT_COMMIT"
git -C "$SRC" checkout --detach "$OCCT_COMMIT"
ACTUAL_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$OCCT_COMMIT" ]]; then
  echo "OCCT source mismatch: expected $OCCT_COMMIT, got $ACTUAL_COMMIT" >&2
  exit 3
fi

cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ANDROID_ABI" \
  -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_ROOT" \
  -DINSTALL_DIR="$INSTALL_ROOT" \
  -DINSTALL_DIR_LAYOUT=Unix \
  -DINSTALL_DIR_WITH_VERSION=OFF \
  -DBUILD_LIBRARY_TYPE=Shared \
  -DBUILD_CPP_STANDARD=C++17 \
  -DBUILD_MODULE_FoundationClasses=ON \
  -DBUILD_MODULE_ModelingData=ON \
  -DBUILD_MODULE_ModelingAlgorithms=ON \
  -DBUILD_MODULE_ApplicationFramework=ON \
  -DBUILD_MODULE_DataExchange=ON \
  -DBUILD_MODULE_Visualization=OFF \
  -DBUILD_MODULE_Draw=OFF \
  -DBUILD_DOC_Overview=OFF \
  -DBUILD_DOC_RefMan=OFF \
  -DBUILD_USE_PCH=OFF \
  -DBUILD_WITH_DEBUG=OFF \
  -DBUILD_RESOURCES=OFF \
  -DUSE_TK=OFF \
  -DUSE_FREETYPE=OFF \
  -DUSE_TBB=OFF \
  -DUSE_VTK=OFF \
  -DUSE_FREEIMAGE=OFF \
  -DUSE_RAPIDJSON=OFF \
  -DUSE_DRACO=OFF

cmake --build "$BUILD" --parallel "$JOBS"
cmake --install "$BUILD"

cat > "$INSTALL_ROOT/brepsight-occt-sdk.json" <<EOF
{
  "occtTag": "$OCCT_TAG",
  "occtCommit": "$OCCT_COMMIT",
  "androidAbi": "$ANDROID_ABI",
  "androidPlatform": "$ANDROID_PLATFORM",
  "libraryType": "shared",
  "cppStandard": "C++17",
  "visualization": false,
  "draw": false,
  "purpose": "BrepSight exact CAD import/export SDK"
}
EOF

# Fail early if the exact STEP/XCAF toolkits needed by BrepSight are absent.
find "$INSTALL_ROOT" -type f -name 'libTKDESTEP.so' -print -quit | grep -q .
find "$INSTALL_ROOT" -type f -name 'libTKXCAF.so' -print -quit | grep -q .
find "$INSTALL_ROOT" -type f -name 'libTKLCAF.so' -print -quit | grep -q .
find "$INSTALL_ROOT" -type f -name 'OpenCASCADEConfig.cmake' -print -quit | grep -q .

echo "OCCT Android SDK ready at: $INSTALL_ROOT"
