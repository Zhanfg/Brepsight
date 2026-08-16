#include <cassert>
#include <cmath>
#include <fstream>
#include <iostream>
#include <string>

#include "obj_importer.h"

namespace {

void expectNear(float actual, float expected) {
  assert(std::fabs(actual - expected) < 1.0e-5f);
}

}  // namespace

int main() {
  const std::string path = "/tmp/brepsight_quad.obj";
  std::ofstream out(path);
  out << "v 0 0 0\n"
         "v 10 0 0\n"
         "v 10 5 0\n"
         "v 0 5 0\n"
         "vt 0 0\n"
         "vt 1 0\n"
         "vt 1 1\n"
         "vt 0 1\n"
         "vn 0 0 1\n"
         "f 1/1/1 2/2/1 3/3/1 4/4/1\n";
  out.close();

  brepsight::MeshData mesh;
  std::string error;
  assert(brepsight::loadObj(path, mesh, error));
  assert(error.empty());
  assert(mesh.sourceFormat == "obj");
  assert(mesh.triangleCount == 2);
  assert(mesh.vertices.size() == 6);
  assert(mesh.hasUv);
  assert(mesh.hasNormals);
  expectNear(mesh.bounds.max.x, 10.0f);
  expectNear(mesh.bounds.max.y, 5.0f);
  expectNear(mesh.vertices[0].uv.x, 0.0f);
  expectNear(mesh.vertices[1].uv.x, 1.0f);
  expectNear(mesh.vertices[2].uv.y, 1.0f);

  std::cout << "OBJ importer tests passed\n";
  return 0;
}
