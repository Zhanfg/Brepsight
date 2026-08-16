#include "mesh_merge.h"

#include <algorithm>
#include <cstddef>
#include <limits>

namespace brepsight {

MeshData mergeMeshes(const std::vector<MeshData>& meshes) {
  MeshData output;
  output.sourceFormat = "merged";
  if (meshes.empty()) return output;

  output.hasNormals = std::all_of(meshes.begin(), meshes.end(), [](const MeshData& mesh) {
    return mesh.hasNormals;
  });
  output.hasUv = std::all_of(meshes.begin(), meshes.end(), [](const MeshData& mesh) {
    return mesh.hasUv;
  });

  std::size_t totalVertices = 0;
  std::size_t totalTriangles = 0;
  for (const MeshData& mesh : meshes) {
    if (mesh.vertices.size() > std::numeric_limits<std::size_t>::max() - totalVertices) {
      return MeshData{};
    }
    if (mesh.triangleCount > std::numeric_limits<std::size_t>::max() - totalTriangles) {
      return MeshData{};
    }
    totalVertices += mesh.vertices.size();
    totalTriangles += mesh.triangleCount;
  }

  output.vertices.reserve(totalVertices);
  for (const MeshData& mesh : meshes) {
    for (const MeshVertex& vertex : mesh.vertices) {
      MeshVertex merged = vertex;
      if (!output.hasUv) merged.uv = {};
      output.vertices.push_back(merged);
      output.bounds.include(merged.position);
    }
  }
  output.triangleCount = totalTriangles;
  return output;
}

}  // namespace brepsight
