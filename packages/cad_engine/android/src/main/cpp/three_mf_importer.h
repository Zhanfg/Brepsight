#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "mesh_document.h"

namespace brepsight {

struct ThreeMfBuildItemInfo {
  std::uint32_t resourceId = 0;
  std::string name;
  std::string partNumber;
  bool meshObject = false;
  bool componentsObject = false;
  std::array<float, 12> transform{};
};

struct ThreeMfPayload {
  std::string modelUnit;
  std::vector<ThreeMfBuildItemInfo> buildItems;
  std::size_t expandedObjectCount = 0;
};

struct ThreeMfImportResult {
  std::shared_ptr<MeshData> displayMesh;
  std::shared_ptr<ThreeMfPayload> payload;
  std::size_t rootObjectCount = 0;
  std::size_t hierarchyNodeCount = 0;
  std::string error;

  bool ok() const {
    return displayMesh != nullptr && !displayMesh->vertices.empty() && error.empty();
  }
};

ThreeMfImportResult importThreeMf(const std::string& path);

}  // namespace brepsight
