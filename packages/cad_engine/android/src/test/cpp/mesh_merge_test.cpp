#include <cassert>
#include <iostream>
#include <vector>

#include "mesh_merge.h"

namespace {

brepsight::MeshData makeTriangle(float offsetX, bool hasUv) {
  brepsight::MeshData mesh;
  mesh.sourceFormat = "test";
  mesh.triangleCount = 1;
  mesh.hasNormals = true;
  mesh.hasUv = hasUv;
  mesh.vertices = {
      {{offsetX + 0, 0, 0}, {0, 0, 1}, {1, 0, 0}, {0, 0}},
      {{offsetX + 1, 0, 0}, {0, 0, 1}, {0, 1, 0}, {1, 0}},
      {{offsetX + 0, 1, 0}, {0, 0, 1}, {0, 0, 1}, {0, 1}},
  };
  for (const auto& vertex : mesh.vertices) mesh.bounds.include(vertex.position);
  return mesh;
}

}  // namespace

int main() {
  const auto left = makeTriangle(0.0f, true);
  const auto right = makeTriangle(10.0f, true);

  const auto completeUv = brepsight::mergeMeshes({left, right});
  assert(completeUv.triangleCount == 2);
  assert(completeUv.vertices.size() == 6);
  assert(completeUv.hasUv);
  assert(completeUv.hasNormals);
  assert(completeUv.bounds.valid);
  assert(completeUv.bounds.min.x == 0.0f);
  assert(completeUv.bounds.max.x == 11.0f);

  auto noUv = makeTriangle(20.0f, false);
  const auto mixed = brepsight::mergeMeshes({left, noUv});
  assert(mixed.triangleCount == 2);
  assert(mixed.vertices.size() == 6);
  assert(!mixed.hasUv);
  for (const auto& vertex : mixed.vertices) {
    assert(vertex.uv.x == 0.0f);
    assert(vertex.uv.y == 0.0f);
  }

  std::cout << "Mesh merge tests passed\n";
  return 0;
}
