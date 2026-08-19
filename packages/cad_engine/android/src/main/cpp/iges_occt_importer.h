#pragma once

#include <cstddef>
#include <memory>
#include <string>

#include "mesh_document.h"

namespace brepsight {

struct IgesOcctImportResult {
  std::shared_ptr<MeshData> displayMesh;
  // Keeps the exact XCAF/OCAF document and B-Rep topology alive without
  // exposing OCCT types through the stable JNI-facing document record.
  std::shared_ptr<void> exactPayload;
  std::size_t rootShapeCount = 0;
  std::size_t hierarchyNodeCount = 0;
  std::string error;
};

// Reads IGES/IGS through IGESCAFControl so names/colors/layers stay in XCAF.
// A tessellated mesh is generated for GLES while exact B-Rep remains alive in
// exactPayload.
IgesOcctImportResult importIgesWithOcct(const std::string& path);

}  // namespace brepsight
