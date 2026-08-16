#pragma once

#include <cstddef>

#include "mesh_document.h"

namespace brepsight {

struct MeshAnalysis {
  Bounds3 bounds;
  std::size_t uniqueVertexCount = 0;
  std::size_t triangleCount = 0;
  std::size_t openEdgeCount = 0;
  std::size_t nonManifoldEdgeCount = 0;
  std::size_t connectedComponentCount = 0;
  std::size_t degenerateTriangleCount = 0;
  double surfaceArea = 0.0;
  double enclosedVolume = 0.0;
  bool closed = false;
};

MeshAnalysis analyzeMesh(const MeshData& mesh);

}  // namespace brepsight
