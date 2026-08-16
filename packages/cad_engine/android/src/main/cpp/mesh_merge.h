#pragma once

#include <vector>

#include "mesh_document.h"

namespace brepsight {

MeshData mergeMeshes(const std::vector<MeshData>& meshes);

}  // namespace brepsight
