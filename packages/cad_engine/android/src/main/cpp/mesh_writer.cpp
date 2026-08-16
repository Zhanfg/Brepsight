#include "mesh_writer.h"

#include <array>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <limits>
#include <string>
#include <vector>

namespace brepsight {
namespace {

void appendU32Le(std::vector<unsigned char>& bytes, uint32_t value) {
  bytes.push_back(static_cast<unsigned char>(value & 0xffU));
  bytes.push_back(static_cast<unsigned char>((value >> 8U) & 0xffU));
  bytes.push_back(static_cast<unsigned char>((value >> 16U) & 0xffU));
  bytes.push_back(static_cast<unsigned char>((value >> 24U) & 0xffU));
}

void appendU16Le(std::vector<unsigned char>& bytes, uint16_t value) {
  bytes.push_back(static_cast<unsigned char>(value & 0xffU));
  bytes.push_back(static_cast<unsigned char>((value >> 8U) & 0xffU));
}

void appendF32Le(std::vector<unsigned char>& bytes, float value) {
  uint32_t bits = 0;
  static_assert(sizeof(bits) == sizeof(value));
  std::memcpy(&bits, &value, sizeof(bits));
  appendU32Le(bytes, bits);
}

}  // namespace

bool writeBinaryStl(const std::string& path, const MeshData& mesh, std::string& error) {
  if (mesh.triangleCount == 0 || mesh.vertices.size() < mesh.triangleCount * 3ULL) {
    error = "Mesh does not contain complete triangles.";
    return false;
  }
  if (mesh.triangleCount > std::numeric_limits<uint32_t>::max()) {
    error = "Mesh has too many triangles for binary STL.";
    return false;
  }

  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  if (!out) {
    error = "Unable to create STL output file.";
    return false;
  }

  std::array<unsigned char, 80> header{};
  const char label[] = "BrepSight binary STL";
  std::memcpy(header.data(), label, sizeof(label) - 1);
  out.write(reinterpret_cast<const char*>(header.data()), static_cast<std::streamsize>(header.size()));

  std::vector<unsigned char> countBytes;
  countBytes.reserve(4);
  appendU32Le(countBytes, static_cast<uint32_t>(mesh.triangleCount));
  out.write(reinterpret_cast<const char*>(countBytes.data()), 4);

  std::vector<unsigned char> record;
  record.reserve(50);
  for (std::size_t triangle = 0; triangle < mesh.triangleCount; ++triangle) {
    record.clear();
    const std::size_t base = triangle * 3ULL;
    const Vec3 normal = mesh.vertices[base].normal;
    appendF32Le(record, normal.x);
    appendF32Le(record, normal.y);
    appendF32Le(record, normal.z);
    for (std::size_t i = 0; i < 3; ++i) {
      const Vec3 p = mesh.vertices[base + i].position;
      appendF32Le(record, p.x);
      appendF32Le(record, p.y);
      appendF32Le(record, p.z);
    }
    appendU16Le(record, 0);
    out.write(reinterpret_cast<const char*>(record.data()), static_cast<std::streamsize>(record.size()));
    if (!out) {
      error = "Failed while writing binary STL data.";
      return false;
    }
  }

  return true;
}

bool writeObj(const std::string& path, const MeshData& mesh, std::string& error) {
  if (mesh.triangleCount == 0 || mesh.vertices.size() < mesh.triangleCount * 3ULL) {
    error = "Mesh does not contain complete triangles.";
    return false;
  }

  std::ofstream out(path, std::ios::trunc);
  if (!out) {
    error = "Unable to create OBJ output file.";
    return false;
  }

  out << "# BrepSight OBJ export\n";
  for (const MeshVertex& vertex : mesh.vertices) {
    out << "v " << vertex.position.x << ' ' << vertex.position.y << ' ' << vertex.position.z << '\n';
  }
  if (mesh.hasUv) {
    for (const MeshVertex& vertex : mesh.vertices) {
      out << "vt " << vertex.uv.x << ' ' << vertex.uv.y << '\n';
    }
  }
  for (const MeshVertex& vertex : mesh.vertices) {
    out << "vn " << vertex.normal.x << ' ' << vertex.normal.y << ' ' << vertex.normal.z << '\n';
  }

  for (std::size_t triangle = 0; triangle < mesh.triangleCount; ++triangle) {
    const std::size_t base = triangle * 3ULL;
    out << "f";
    for (std::size_t i = 0; i < 3; ++i) {
      const std::size_t index = base + i + 1ULL;
      if (mesh.hasUv) {
        out << ' ' << index << '/' << index << '/' << index;
      } else {
        out << ' ' << index << "//" << index;
      }
    }
    out << '\n';
  }

  if (!out) {
    error = "Failed while writing OBJ data.";
    return false;
  }
  return true;
}

}  // namespace brepsight
