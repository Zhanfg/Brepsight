#pragma once

#include <string>

#include "mesh_document.h"

namespace brepsight {

bool loadObj(const std::string& path, MeshData& out, std::string& error);

}  // namespace brepsight
