#include "mesh_transform.h"
#include "mesh_writer.h"

#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace {

bool near(float actual, float expected, float epsilon = 1.0e-4f) {
  return std::fabs(actual - expected) <= epsilon;
}

brepsight::MeshData makeTriangle() {
  brepsight::MeshData mesh;
  const float invSqrt2 = 1.0f / std::sqrt(2.0f);
  mesh.vertices = {
      {{0.0f, 0.0f, 0.0f}, {invSqrt2, invSqrt2, 0.0f}, {}, {}},
      {{2.0f, 0.0f, 0.0f}, {invSqrt2, invSqrt2, 0.0f}, {}, {}},
      {{0.0f, 2.0f, 0.0f}, {invSqrt2, invSqrt2, 0.0f}, {}, {}},
  };
  for (const auto& vertex : mesh.vertices) mesh.bounds.include(vertex.position);
  mesh.triangleCount = 1;
  mesh.hasNormals = true;
  return mesh;
}

float readF32Le(const std::array<unsigned char, 4>& bytes) {
  const std::uint32_t bits =
      static_cast<std::uint32_t>(bytes[0]) |
      (static_cast<std::uint32_t>(bytes[1]) << 8U) |
      (static_cast<std::uint32_t>(bytes[2]) << 16U) |
      (static_cast<std::uint32_t>(bytes[3]) << 24U);
  float value = 0.0f;
  static_assert(sizeof(value) == sizeof(bits));
  std::memcpy(&value, &bits, sizeof(value));
  return value;
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

  // The product export path writes currentMesh(), so prove that a mutated
  // working-copy mesh is serialized rather than the pre-edit coordinates.
  {
    auto mesh = makeTriangle();
    brepsight::MeshTransform transform;
    transform.translation = {7.0f, 8.0f, 9.0f};
    assert(brepsight::applyMeshTransform(mesh, transform, error));

    const auto tempRoot = std::filesystem::temp_directory_path();
    const auto objPath = tempRoot / "brepsight_edit_export_contract.obj";
    const auto stlPath = tempRoot / "brepsight_edit_export_contract.stl";

    error.clear();
    assert(brepsight::writeObj(objPath.string(), mesh, error));
    assert(error.empty());
    std::ifstream obj(objPath);
    const std::string objText((std::istreambuf_iterator<char>(obj)), std::istreambuf_iterator<char>());
    assert(objText.find("v 7 8 9") != std::string::npos);
    assert(objText.find("v 9 8 9") != std::string::npos);
    assert(objText.find("v 7 10 9") != std::string::npos);

    error.clear();
    assert(brepsight::writeBinaryStl(stlPath.string(), mesh, error));
    assert(error.empty());
    assert(std::filesystem::file_size(stlPath) == 84U + 50U);
    std::ifstream stl(stlPath, std::ios::binary);
    stl.seekg(84 + 12);  // STL header/count + triangle normal.
    std::array<unsigned char, 4> xBytes{};
    std::array<unsigned char, 4> yBytes{};
    std::array<unsigned char, 4> zBytes{};
    stl.read(reinterpret_cast<char*>(xBytes.data()), 4);
    stl.read(reinterpret_cast<char*>(yBytes.data()), 4);
    stl.read(reinterpret_cast<char*>(zBytes.data()), 4);
    assert(stl.good());
    assert(near(readF32Le(xBytes), 7.0f));
    assert(near(readF32Le(yBytes), 8.0f));
    assert(near(readF32Le(zBytes), 9.0f));

    std::filesystem::remove(objPath);
    std::filesystem::remove(stlPath);
  }

  return 0;
}
