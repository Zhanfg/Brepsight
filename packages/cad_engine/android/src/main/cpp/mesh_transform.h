#pragma once

#include <string>

#include "mesh_document.h"

namespace brepsight {

struct MeshTransform {
  Vec3 translation{};
  Vec3 rotationDegrees{};
  Vec3 scale{1.0f, 1.0f, 1.0f};
};

// Applies an affine working-copy transform around the current mesh bounds
// center. Translation is applied after scale+rotation. Positive non-zero scale
// is required so triangle winding remains stable.
bool applyMeshTransform(MeshData& mesh, const MeshTransform& transform, std::string& error);

}  // namespace brepsight
