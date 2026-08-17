#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

#include "mesh_document.h"

namespace brepsight {

struct FcStdShapePayload {
  std::string objectName;
  std::shared_ptr<void> exactPayload;
};

struct FcStdPayload {
  std::string originalSourcePath;
  std::vector<FcStdShapePayload> shapes;
  std::size_t documentObjectCount = 0;
  std::size_t skippedShapeCount = 0;
  bool readOnly = true;
  bool recomputed = false;
};

struct FcStdImportResult {
  std::shared_ptr<MeshData> displayMesh;
  std::shared_ptr<FcStdPayload> payload;
  std::string sourcePathOverride;
  std::string error;
  std::size_t rootObjectCount = 0;
  std::size_t hierarchyNodeCount = 0;

  bool ok() const {
    return displayMesh != nullptr && !displayMesh->vertices.empty() &&
        payload != nullptr && !payload->shapes.empty();
  }
};

// Consumes a BrepSight-generated manifest produced by FcStdArchivePreparer.
// The original FCStd ZIP is never parsed by native code and no document code is executed.
FcStdImportResult importPreparedFcStd(const std::string& manifestPath);

}  // namespace brepsight
