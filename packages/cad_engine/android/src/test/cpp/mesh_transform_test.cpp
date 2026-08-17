#include "mesh_transform.h"

#include <cassert>
#include <cmath>
#include <string>

namespace {

bool near(float actual, float expected, float epsilon = 1.0e-4f) {
  return std::fabs(actual - expected) <= epsilon;
}

brepsight::MeshData makeTriangle() {
  brepsight::MeshData mesh;
  const float invSqrt2 = 1.0f / std::sqrt(2.0f);
  mesh.vertices = {
      {{{0.0f, 0.0f, 0.0f}}, {invSqrt2, invSqrt2, 0.0f}, {}, {}},
      {{{2.0f, 0.0f, 0.0f}}, {invSqrt2, invSqrt2, 0.0f}, {}, {}},
      {{{0.0f, 2.0f, 0.0f}}, {invSqrt2, invSqrt2, 0.0f}, {}, {}},
  };
  for (const auto& vertex : mesh.vertices) mesh.bounds.include(vertex.position);
  mesh.triangleCount = 1;
  mesh.hasNormals = true;
  return mesh;
}

}  // namespace

int main() {
  std::string error;

  {
    auto mesh = makeTriangle();
    brepsight::MeshTransform transform;
    transform.translation = {3.0f, -2.0f, 5.0f};
    assert(brepsight::applyMeshTransform(mesh, transform, error));
    assert(error.empty());
    assert(near(mesh.vertices[0].position.x, 3.0f));
    assert(near(mesh.vertices[0].position.y, -2.0f));
    assert(near(mesh.vertices[0].position.z, 5.0f));
    assert(near(mesh.bounds.min.x, 3.0f));
    assert(near(mesh.bounds.max.x, 5.0f));
    assert(near(mesh.bounds.min.y, -2.0f));
    assert(near(mesh.bounds.max.y, 0.0f));
  }

  {
    auto mesh = makeTriangle();
    brepsight::MeshTransform transform;
    transform.rotationDegrees = {0.0f, 0.0f, 90.0f};
    assert(brepsight::applyMeshTransform(mesh, transform, error));
    assert(near(mesh.vertices[0].position.x, 2.0f));
    assert(near(mesh.vertices[0].position.y, 0.0f));
    assert(near(mesh.vertices[1].position.x, 2.0f));
    assert(near(mesh.vertices[1].position.y, 2.0f));
    assert(near(mesh.vertices[2].position.x, 0.0f));
    assert(near(mesh.vertices[2].position.y, 0.0f));
  }

  {
    auto mesh = makeTriangle();
    brepsight::MeshTransform transform;
    transform.scale = {2.0f, 1.0f, 1.0f};
    assert(brepsight::applyMeshTransform(mesh, transform, error));
    assert(near(mesh.bounds.min.x, -1.0f));
    assert(near(mesh.bounds.max.x, 3.0f));
    assert(near(mesh.bounds.min.y, 0.0f));
    assert(near(mesh.bounds.max.y, 2.0f));
    assert(near(mesh.vertices[0].normal.x, 0.4472136f));
    assert(near(mesh.vertices[0].normal.y, 0.8944272f));
  }

  {
    auto mesh = makeTriangle();
    const auto original = mesh.vertices[0].position;
    brepsight::MeshTransform transform;
    transform.scale = {0.0f, 1.0f, 1.0f};
    assert(!brepsight::applyMeshTransform(mesh, transform, error));
    assert(!error.empty());
    assert(near(mesh.vertices[0].position.x, original.x));
    assert(near(mesh.vertices[0].position.y, original.y));
    assert(near(mesh.vertices[0].position.z, original.z));
  }

  return 0;
}
