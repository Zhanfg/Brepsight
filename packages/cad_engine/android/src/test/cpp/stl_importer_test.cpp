#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "stl_importer.h"

namespace {

void putU32Le(std::vector<unsigned char>& bytes, std::size_t offset, uint32_t value) {
  bytes[offset + 0] = static_cast<unsigned char>(value & 0xffU);
  bytes[offset + 1] = static_cast<unsigned char>((value >> 8U) & 0xffU);
  bytes[offset + 2] = static_cast<unsigned char>((value >> 16U) & 0xffU);
  bytes[offset + 3] = static_cast<unsigned char>((value >> 24U) & 0xffU);
}

void putF32Le(std::vector<unsigned char>& bytes, std::size_t offset, float value) {
  uint32_t bits = 0;
  static_assert(sizeof(bits) == sizeof(value));
  std::memcpy(&bits, &value, sizeof(bits));
  putU32Le(bytes, offset, bits);
}

void expectNear(float actual, float expected) {
  assert(std::fabs(actual - expected) < 1.0e-5f);
}

void testAscii() {
  const std::string path = "/tmp/brepsight_ascii.stl";
  std::ofstream out(path);
  out << "solid triangle\n"
         "facet normal 0 0 1\n"
         "outer loop\n"
         "vertex 0 0 0\n"
         "vertex 10 0 0\n"
         "vertex 0 5 0\n"
         "endloop\n"
         "endfacet\n"
         "endsolid triangle\n";
  out.close();

  brepsight::MeshData mesh;
  std::string error;
  assert(brepsight::loadStl(path, mesh, error));
  assert(error.empty());
  assert(mesh.sourceFormat == "stl-ascii");
  assert(mesh.triangleCount == 1);
  assert(mesh.vertices.size() == 3);
  assert(mesh.bounds.valid);
  expectNear(mesh.bounds.min.x, 0.0f);
  expectNear(mesh.bounds.max.x, 10.0f);
  expectNear(mesh.bounds.max.y, 5.0f);
  expectNear(mesh.vertices[0].normal.z, 1.0f);
}

void testBinary() {
  const std::string path = "/tmp/brepsight_binary.stl";
  std::vector<unsigned char> bytes(84 + 50, 0);
  putU32Le(bytes, 80, 1);
  std::size_t cursor = 84;
  putF32Le(bytes, cursor + 8, 1.0f);  // normal z
  putF32Le(bytes, cursor + 12, 0.0f);
  putF32Le(bytes, cursor + 16, 0.0f);
  putF32Le(bytes, cursor + 20, 0.0f);
  putF32Le(bytes, cursor + 24, 2.0f);
  putF32Le(bytes, cursor + 28, 0.0f);
  putF32Le(bytes, cursor + 32, 0.0f);
  putF32Le(bytes, cursor + 36, 0.0f);
  putF32Le(bytes, cursor + 40, 3.0f);
  putF32Le(bytes, cursor + 44, 0.0f);

  std::ofstream out(path, std::ios::binary);
  out.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  out.close();

  brepsight::MeshData mesh;
  std::string error;
  assert(brepsight::loadStl(path, mesh, error));
  assert(error.empty());
  assert(mesh.sourceFormat == "stl-binary");
  assert(mesh.triangleCount == 1);
  assert(mesh.vertices.size() == 3);
  expectNear(mesh.bounds.max.x, 2.0f);
  expectNear(mesh.bounds.max.y, 3.0f);
}

}  // namespace

int main() {
  testAscii();
  testBinary();
  std::cout << "STL importer tests passed\n";
  return 0;
}
