#pragma once

#include <cstddef>
#include <memory>
#include <string>

#include "mesh_document.h"

namespace brepsight {

struct RuntimeLoadResult {
  std::shared_ptr<MeshData> mesh;
  std::shared_ptr<void> providerPayload;
  std::string formatId;
  std::string error;
  std::string sourcePathOverride;
  bool exactGeometry = false;
  std::size_t rootObjectCount = 0;
  std::size_t hierarchyNodeCount = 0;

  bool ok() const { return mesh != nullptr && !mesh->vertices.empty(); }
};

// Chooses the native provider by source format while keeping provider-specific
// ABI out of JNI. Exact providers may return both a display mesh and an opaque
// exact payload. Prepared/container providers can preserve the user's original
// source path through sourcePathOverride instead of exposing cache internals.
RuntimeLoadResult loadRuntimeModel(const std::string& path);

}  // namespace brepsight
