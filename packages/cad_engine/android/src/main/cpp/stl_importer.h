#pragma once

#include <cctype>
#include <string>

#include "mesh_document.h"

namespace brepsight {

bool loadStl(const std::string& path, MeshData& out, std::string& error);

}  // namespace brepsight
