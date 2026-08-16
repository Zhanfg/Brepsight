#pragma once

#include <cstddef>
#include <memory>
#include <string>

#include "mesh_document.h"

namespace brepsight {

struct StepOcctImportResult {
  std::shared_ptr<MeshData> displayMesh;
  // Keeps the exact XCAF/OCAF document and B-Rep topology alive without
  // exposing OCCT types through the stable JNI-facing document record.
  std::shared_ptr<void> exactPayload;
  std::size_t rootShapeCount = 0;
  std::size_t assemblyNodeCount = 0;
  std::string error;
};

// Reads STEP through STEPCAFControl so names/colors/assembly structure remain in
// XCAF. A tessellated mesh is generated only for the current GLES display path;
// exact B-Rep remains owned by exactPayload.
StepOcctImportResult importStepWithOcct(const std::string& path);

}  // namespace brepsight
