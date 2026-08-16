#include <cassert>
#include <iostream>

#include "mesh_components.h"

namespace {

void appendTriangle(
    brepsight::MeshData& mesh,
    const brepsight::Vec3& a,
    const brepsight::Vec3& b,
    const brepsight::Vec3& c) {
  const brepsight::Vec3 normal{0, 0, 1};
  mesh.vertices.push_back({a, normal, {1, 0, 0}, {0, 0}});
  mesh.vertices.push_back({b, normal, {0, 1, 0}, {1, 0}});
  mesh.vertices.push_back({c, normal, {0, 0, 1}, {0, 1}});
  mesh.bounds.include(a);
  mesh.bounds.include(b);
  mesh.bounds.include(c);
  ++mesh.triangleCount;
}

}  // namespace

int main() {
  brepsight::MeshData mesh;
  mesh.hasNormals = true;
  mesh.hasUv = true;

  appendTriangle(mesh, {0, 0, 0}, {1, 0, 0}, {1, 1, 0});
  appendTriangle(mesh, {0, 0, 0}, {1, 1, 0}, {0, 1, 0});
  appendTriangle(mesh, {10, 0, 0}, {11, 0, 0}, {10, 1, 0});

  const auto components = brepsight::splitConnectedComponents(mesh);
  assert(components.size() == 2);
  assert(components[0].triangleCount == 2);
  assert(components[1].triangleCount == 1);
  assert(components[0].hasUv && components[1].hasUv);
  assert(components[0].hasNormals && components[1].hasNormals);

  std::cout << "Mesh component splitting tests passed\n";
  return 0;
}
