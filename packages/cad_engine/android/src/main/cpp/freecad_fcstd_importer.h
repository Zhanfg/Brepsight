#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "mesh_document.h"

namespace brepsight {

struct FcStdTransform {
  double tx = 0.0;
  double ty = 0.0;
  double tz = 0.0;
  double qx = 0.0;
  double qy = 0.0;
  double qz = 0.0;
  double qw = 1.0;
};

struct FcStdObjectPayload {
  std::string name;
  std::string type;
  std::string label;
  std::string parentName;
  FcStdTransform localTransform;
  FcStdTransform worldTransform;
  bool hasVisibility = false;
  bool visible = true;
  bool hasShapeColor = false;
  std::uint32_t shapeColor = 0;
};

struct FcStdShapePayload {
  std::string objectName;
  std::shared_ptr<void> exactPayload;
};

struct FcStdPayload {
  std::string originalSourcePath;
  std::vector<FcStdObjectPayload> objects;
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
