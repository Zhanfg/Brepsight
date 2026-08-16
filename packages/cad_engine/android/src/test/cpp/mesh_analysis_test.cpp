#include <cassert>
#include <cmath>
#include <iostream>

#include "mesh_analysis.h"

namespace {

void appendTriangle(
    brepsight::MeshData& mesh,
    const brepsight::Vec3& a,
    const brepsight::Vec3& b,
    const brepsight::Vec3& c) {
  const brepsight::Vec3 normal{0, 0, 1};
  mesh.vertices.push_back({a, normal, {1, 0, 0}, {0, 0}});
  mesh.vertices.push_back({b, normal, {0, 1, 0}, {0, 0}});
  mesh.vertices.push_back({c, normal, {0, 0, 1}, {0, 0}});
  mesh.bounds.include(a);
  mesh.bounds.include(b);
  mesh.bounds.include(c);
  ++mesh.triangleCount;
}

void expectNear(double actual, double expected, double epsilon = 1.0e-6) {
  assert(std::fabs(actual - expected) < epsilon);
}

void testClosedTetrahedron() {
  brepsight::MeshData mesh;
  const brepsight::Vec3 p0{0, 0, 0};
  const brepsight::Vec3 p1{1, 0, 0};
  const brepsight::Vec3 p2{0, 1, 0};
  const brepsight::Vec3 p3{0, 0, 1};

  appendTriangle(mesh, p0, p2, p1);
  appendTriangle(mesh, p0, p1, p3);
  appendTriangle(mesh, p0, p3, p2);
  appendTriangle(mesh, p1, p2, p3);

  const brepsight::MeshAnalysis analysis = brepsight::analyzeMesh(mesh);
  assert(analysis.triangleCount == 4);
  assert(analysis.uniqueVertexCount == 4);
  assert(analysis.openEdgeCount == 0);
  assert(analysis.nonManifoldEdgeCount == 0);
  assert(analysis.connectedComponentCount == 1);
  assert(analysis.degenerateTriangleCount == 0);
  assert(analysis.closed);
  expectNear(analysis.enclosedVolume, 1.0 / 6.0);
}

void testOpenTriangle() {
  brepsight::MeshData mesh;
  appendTriangle(mesh, {0, 0, 0}, {2, 0, 0}, {0, 3, 0});

  const brepsight::MeshAnalysis analysis = brepsight::analyzeMesh(mesh);
  assert(analysis.triangleCount == 1);
  assert(analysis.uniqueVertexCount == 3);
  assert(analysis.openEdgeCount == 3);
  assert(!analysis.closed);
  assert(analysis.connectedComponentCount == 1);
  expectNear(analysis.surfaceArea, 3.0);
  expectNear(analysis.enclosedVolume, 0.0);
}

}  // namespace

int main() {
  testClosedTetrahedron();
  testOpenTriangle();
  std::cout << "Mesh analysis tests passed\n";
  return 0;
}
