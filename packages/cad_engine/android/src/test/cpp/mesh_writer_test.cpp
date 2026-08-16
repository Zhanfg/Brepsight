#include <cassert>
#include <iostream>
#include <string>

#include "mesh_writer.h"
#include "obj_importer.h"
#include "stl_importer.h"

namespace {

brepsight::MeshData makeTriangle() {
  brepsight::MeshData mesh;
  mesh.sourceFormat = "test";
  mesh.triangleCount = 1;
  mesh.hasNormals = true;
  mesh.hasUv = true;
  mesh.vertices = {
      {{0, 0, 0}, {0, 0, 1}, {1, 0, 0}, {0, 0}},
      {{2, 0, 0}, {0, 0, 1}, {0, 1, 0}, {1, 0}},
      {{0, 3, 0}, {0, 0, 1}, {0, 0, 1}, {0, 1}},
  };
  for (const auto& vertex : mesh.vertices) mesh.bounds.include(vertex.position);
  return mesh;
}

}  // namespace

int main() {
  const auto source = makeTriangle();
  std::string error;

  const std::string stlPath = "/tmp/brepsight_writer.stl";
  assert(brepsight::writeBinaryStl(stlPath, source, error));
  assert(error.empty());
  brepsight::MeshData stlRoundTrip;
  assert(brepsight::loadStl(stlPath, stlRoundTrip, error));
  assert(stlRoundTrip.triangleCount == 1);
  assert(!stlRoundTrip.hasUv);

  error.clear();
  const std::string objPath = "/tmp/brepsight_writer.obj";
  assert(brepsight::writeObj(objPath, source, error));
  assert(error.empty());
  brepsight::MeshData objRoundTrip;
  assert(brepsight::loadObj(objPath, objRoundTrip, error));
  assert(objRoundTrip.triangleCount == 1);
  assert(objRoundTrip.hasUv);

  std::cout << "Mesh writer round-trip tests passed\n";
  return 0;
}
