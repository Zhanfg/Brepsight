#pragma once

#include <string>

#include "mesh_document.h"

namespace brepsight {

// Recomputes effective object visibility, linked draw-range visibility and
// visible bounds. Returns false for invalid object graphs or draw ranges.
bool refreshMeshPresentation(MeshData& mesh, std::string& error);

// Changes one object's local visibility and refreshes all inherited state.
bool setMeshObjectVisibility(
    MeshData& mesh,
    const std::string& objectId,
    bool visible,
    std::string& error);

// Compact JSON snapshot for the Flutter/Kotlin bridge.
std::string meshObjectPresentationJson(const MeshData& mesh);

}  // namespace brepsight
