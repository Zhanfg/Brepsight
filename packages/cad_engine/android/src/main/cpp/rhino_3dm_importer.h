#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

#include "mesh_document.h"

namespace brepsight {

struct Rhino3dmPayload {
  std::size_t geometryObjectCount = 0;
  std::size_t renderMeshObjectCount = 0;
  std::vector<std::string> warnings;
};

struct Rhino3dmImportResult {
  std::shared_ptr<MeshData> displayMesh;
  std::shared_ptr<Rhino3dmPayload> payload;
  std::size_t rootObjectCount = 0;
  std::size_t hierarchyNodeCount = 0;
  std::string error;
};

// Reads Rhino 3DM with openNURBS. Version 0.1 intentionally prioritizes saved
// render meshes (including render meshes attached to Breps/extrusions), which
// preserves a safe read-only mobile display path without pretending to recover
// Rhino parametric history.
Rhino3dmImportResult importRhino3dm(const std::string& path);

}  // namespace brepsight
