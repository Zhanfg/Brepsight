#pragma once

#include <memory>
#include <string>

#include "mesh_document.h"

namespace brepsight {

struct BrepOcctImportResult {
  std::shared_ptr<MeshData> displayMesh;
  std::shared_ptr<void> exactPayload;
  std::string error;

  bool ok() const {
    return displayMesh != nullptr && !displayMesh->vertices.empty() && exactPayload != nullptr;
  }
};

BrepOcctImportResult importBrepWithOcct(const std::string& path);

}  // namespace brepsight
