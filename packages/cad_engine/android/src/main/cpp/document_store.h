#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

#include "mesh_document.h"

namespace brepsight {

// Native document metadata shared by mesh-only and exact-geometry providers.
// providerPayload deliberately stays type-erased so OCCT/openNURBS/etc. do not
// leak their ABI into the JNI/Flutter contract.
struct NativeDocumentRecord {
  int64_t handle = 0;
  std::string sourcePath;
  std::string formatId;
  bool committed = false;

  std::shared_ptr<MeshData> displayMesh;
  std::shared_ptr<void> providerPayload;

  bool exactGeometry = false;
  std::size_t rootObjectCount = 0;
  std::size_t hierarchyNodeCount = 0;
};

}  // namespace brepsight
