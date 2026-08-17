#!/usr/bin/env bash
set -euo pipefail

OCCT_TAG="${OCCT_TAG:-V8_0_0}"
OCCT_COMMIT="${OCCT_COMMIT:-d3056ef80c9668f395da40f5fd7be186cae4501f}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/.build/occt-host}"
INSTALL_ROOT="${INSTALL_ROOT:-$PWD/.build/occt-host-sdk}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

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
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$OCCT_COMMIT" ]] || {
  echo "OCCT source identity mismatch" >&2
  exit 3
}

cmake -S "$SRC" -B "$BUILD" -G Ninja \
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

cat > "$INSTALL_ROOT/brepsight-occt-host-sdk.json" <<EOF
{
  "occtTag": "$OCCT_TAG",
  "occtCommit": "$OCCT_COMMIT",
  "purpose": "BrepSight host-side semantic contract fixtures"
}
EOF

find "$INSTALL_ROOT" -type f -name 'libTKDEIGES.so*' -print -quit | grep -q .
find "$INSTALL_ROOT" -type f -name 'libTKXCAF.so*' -print -quit | grep -q .
find "$INSTALL_ROOT" -type f -name 'libTKPrim.so*' -print -quit | grep -q .
find "$INSTALL_ROOT" -type f -name 'OpenCASCADEConfig.cmake' -print -quit | grep -q .

echo "OCCT host SDK ready at: $INSTALL_ROOT"
