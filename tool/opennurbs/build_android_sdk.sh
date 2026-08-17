#!/usr/bin/env bash
set -euo pipefail

OPENNURBS_COMMIT="${OPENNURBS_COMMIT:-00bdd2ce8f3e4cd3d4921343909bbe123b2e9d58}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-24}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/.build/opennurbs-android}"
INSTALL_ROOT="${INSTALL_ROOT:-$PWD/.build/opennurbs-sdk/${ANDROID_ABI}}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
LOG_ROOT="$BUILD_ROOT/logs"

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point to an Android NDK installation}"
TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
[[ -f "$TOOLCHAIN" ]] || { echo "Android NDK toolchain not found: $TOOLCHAIN" >&2; exit 2; }

SRC="$BUILD_ROOT/src"
BUILD="$BUILD_ROOT/build"
rm -rf "$BUILD" "$INSTALL_ROOT"
mkdir -p "$BUILD_ROOT" "$BUILD" "$INSTALL_ROOT/include" "$INSTALL_ROOT/lib" "$LOG_ROOT"

if [[ ! -d "$SRC/.git" ]]; then
  rm -rf "$SRC"
  git clone --filter=blob:none --no-checkout https://github.com/mcneel/opennurbs.git "$SRC"
fi
git -C "$SRC" fetch --depth=1 origin "$OPENNURBS_COMMIT"
git -C "$SRC" checkout --detach "$OPENNURBS_COMMIT"
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$OPENNURBS_COMMIT" ]] || {
  echo "openNURBS source identity mismatch" >&2
  exit 3
}

cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ANDROID_ABI" \
  -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  2>&1 | tee "$LOG_ROOT/configure.log"

cmake --build "$BUILD" --target OpenNURBS --parallel "$JOBS" \
  2>&1 | tee "$LOG_ROOT/build.log"

LIBRARY="$(find "$BUILD" -type f \( -name 'libOpenNURBS.so' -o -name 'OpenNURBS.so' \) -print -quit)"
[[ -n "$LIBRARY" && -f "$LIBRARY" ]] || {
  echo "OpenNURBS shared library was not produced." >&2
  find "$BUILD" -maxdepth 5 -type f -name '*.so' -print >&2 || true
  exit 4
}
cp "$LIBRARY" "$INSTALL_ROOT/lib/libOpenNURBS.so"
find "$SRC" -maxdepth 1 -type f -name '*.h' -exec cp {} "$INSTALL_ROOT/include/" \;
[[ -f "$INSTALL_ROOT/include/opennurbs_public.h" ]] || {
  echo "openNURBS public headers are incomplete." >&2
  exit 5
}

cat > "$INSTALL_ROOT/brepsight-opennurbs-sdk.json" <<EOF
{
  "openNurbsCommit": "$OPENNURBS_COMMIT",
  "androidAbi": "$ANDROID_ABI",
  "androidPlatform": "$ANDROID_PLATFORM",
  "library": "libOpenNURBS.so",
  "provider": "rhino-3dm-saved-render-mesh",
  "purpose": "BrepSight 0.1 Rhino 3DM read-only provider"
}
EOF

readelf -d "$INSTALL_ROOT/lib/libOpenNURBS.so" > "$LOG_ROOT/readelf.txt"
echo "openNURBS Android SDK ready at: $INSTALL_ROOT"
