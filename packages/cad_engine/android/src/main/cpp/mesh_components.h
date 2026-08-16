#pragma once

#include <vector>

#include "mesh_document.h"

namespace brepsight {

std::vector<MeshData> splitConnectedComponents(const MeshData& mesh);

}  // namespace brepsight
