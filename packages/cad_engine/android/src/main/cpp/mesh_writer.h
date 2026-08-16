#pragma once

#include <string>

#include "mesh_document.h"

namespace brepsight {

bool writeBinaryStl(const std::string& path, const MeshData& mesh, std::string& error);
bool writeObj(const std::string& path, const MeshData& mesh, std::string& error);

}  // namespace brepsight
