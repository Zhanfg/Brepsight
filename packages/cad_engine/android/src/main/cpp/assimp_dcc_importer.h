#pragma once

#include <array>
#include <cstddef>
#include <memory>
#include <string>
#include <vector>

#include "mesh_document.h"

namespace brepsight {

struct AssimpMaterialInfo {
  std::string name;
  bool hasDiffuseColor = false;
  Vec3 diffuseColor{0.70f, 0.76f, 0.84f};
  std::size_t diffuseTextureCount = 0;
};

struct AssimpNodeInfo {
  std::string id;
  std::string name;
  std::string parentId;
  std::array<double, 16> localTransform{};
  std::vector<unsigned int> meshIndices;
};

struct AssimpDccPayload {
  std::string sourceFormat;
  std::vector<AssimpNodeInfo> nodes;
  std::vector<AssimpMaterialInfo> materials;
  std::size_t cameraCount = 0;
  std::size_t animationCount = 0;
  bool hasTangents = false;
  bool hasTextures = false;
  std::vector<std::string> warnings;
};

struct AssimpDccImportResult {
  std::shared_ptr<MeshData> displayMesh;
  std::shared_ptr<AssimpDccPayload> payload;
  std::size_t rootObjectCount = 0;
  std::size_t hierarchyNodeCount = 0;
  std::string error;

  bool ok() const {
    return displayMesh != nullptr && !displayMesh->vertices.empty() &&
        payload != nullptr && error.empty();
  }
};

// BrepSight enables this provider only for a deliberately validated subset of
// Assimp importers. The caller supplies the normalized source format id
// (currently fbx, dae, ply, or off); native .blend is intentionally excluded.
AssimpDccImportResult importDccWithAssimp(
    const std::string& path,
    const std::string& sourceFormat);

}  // namespace brepsight
