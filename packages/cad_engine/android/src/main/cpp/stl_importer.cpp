#include "stl_importer.h"

#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace brepsight {
namespace {

Vec3 subtract(const Vec3& a, const Vec3& b) {
  return {a.x - b.x, a.y - b.y, a.z - b.z};
}

Vec3 cross(const Vec3& a, const Vec3& b) {
  return {
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x,
  };
}

float lengthSquared(const Vec3& v) {
  return v.x * v.x + v.y * v.y + v.z * v.z;
}

Vec3 normalize(Vec3 v) {
  const float len2 = lengthSquared(v);
  if (len2 <= 1.0e-20f) return {0.0f, 0.0f, 1.0f};
  const float inv = 1.0f / std::sqrt(len2);
  return {v.x * inv, v.y * inv, v.z * inv};
}

Vec3 triangleNormal(const std::array<Vec3, 3>& p, Vec3 declared) {
  if (lengthSquared(declared) > 1.0e-20f) return normalize(declared);
  return normalize(cross(subtract(p[1], p[0]), subtract(p[2], p[0])));
}

void appendTriangle(MeshData& out, const std::array<Vec3, 3>& p, Vec3 normal) {
  const Vec3 n = triangleNormal(p, normal);
  static constexpr std::array<Vec3, 3> bary = {
      Vec3{1.0f, 0.0f, 0.0f},
      Vec3{0.0f, 1.0f, 0.0f},
      Vec3{0.0f, 0.0f, 1.0f},
  };
  for (std::size_t i = 0; i < 3; ++i) {
    out.vertices.push_back({p[i], n, bary[i]});
    out.bounds.include(p[i]);
  }
  ++out.triangleCount;
}

uint32_t readU32Le(const unsigned char* p) {
  return static_cast<uint32_t>(p[0]) |
         (static_cast<uint32_t>(p[1]) << 8U) |
         (static_cast<uint32_t>(p[2]) << 16U) |
         (static_cast<uint32_t>(p[3]) << 24U);
}

float readF32Le(const unsigned char* p) {
  const uint32_t bits = readU32Le(p);
  float out = 0.0f;
  std::memcpy(&out, &bits, sizeof(out));
  return out;
}

bool loadBinary(const std::vector<unsigned char>& bytes, MeshData& out, std::string& error) {
  if (bytes.size() < 84) return false;
  const uint32_t count = readU32Le(bytes.data() + 80);
  constexpr std::size_t kRecordSize = 50;
  const std::size_t expected = 84ULL + static_cast<std::size_t>(count) * kRecordSize;
  if (expected != bytes.size()) return false;
  if (count > 20'000'000U) {
    error = "STL triangle count is too large for the mobile importer.";
    return false;
  }

  out.vertices.reserve(static_cast<std::size_t>(count) * 3ULL);
  const unsigned char* cursor = bytes.data() + 84;
  for (uint32_t i = 0; i < count; ++i, cursor += kRecordSize) {
    const Vec3 declared{
        readF32Le(cursor + 0), readF32Le(cursor + 4), readF32Le(cursor + 8)};
    std::array<Vec3, 3> p{};
    for (int v = 0; v < 3; ++v) {
      const unsigned char* base = cursor + 12 + v * 12;
      p[static_cast<std::size_t>(v)] = {
          readF32Le(base + 0), readF32Le(base + 4), readF32Le(base + 8)};
    }
    appendTriangle(out, p, declared);
  }
  out.sourceFormat = "stl-binary";
  return out.triangleCount > 0;
}

bool loadAscii(const std::string& text, MeshData& out, std::string& error) {
  std::istringstream in(text);
  std::string token;
  Vec3 declared{0.0f, 0.0f, 1.0f};
  std::array<Vec3, 3> p{};
  int vertexCount = 0;

  while (in >> token) {
    if (token == "facet") {
      std::string normalToken;
      if (!(in >> normalToken) || normalToken != "normal" ||
          !(in >> declared.x >> declared.y >> declared.z)) {
        error = "Malformed ASCII STL facet normal.";
        return false;
      }
      vertexCount = 0;
    } else if (token == "vertex") {
      Vec3 v{};
      if (!(in >> v.x >> v.y >> v.z)) {
        error = "Malformed ASCII STL vertex.";
        return false;
      }
      if (vertexCount < 3) p[static_cast<std::size_t>(vertexCount)] = v;
      ++vertexCount;
    } else if (token == "endfacet") {
      if (vertexCount != 3) {
        error = "ASCII STL facet does not contain exactly three vertices.";
        return false;
      }
      appendTriangle(out, p, declared);
      vertexCount = 0;
    }
  }

  if (out.triangleCount == 0) {
    error = "No triangles were found in the ASCII STL file.";
    return false;
  }
  out.sourceFormat = "stl-ascii";
  return true;
}

}  // namespace

bool loadStl(const std::string& path, MeshData& out, std::string& error) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    error = "Unable to open STL file.";
    return false;
  }

  file.seekg(0, std::ios::end);
  const std::streamoff length = file.tellg();
  if (length <= 0) {
    error = "STL file is empty.";
    return false;
  }
  file.seekg(0, std::ios::beg);

  std::vector<unsigned char> bytes(static_cast<std::size_t>(length));
  if (!file.read(reinterpret_cast<char*>(bytes.data()), length)) {
    error = "Failed while reading STL file.";
    return false;
  }

  MeshData parsed;
  std::string binaryError;
  if (loadBinary(bytes, parsed, binaryError)) {
    out = std::move(parsed);
    return true;
  }
  if (!binaryError.empty()) {
    error = binaryError;
    return false;
  }

  const std::string text(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  parsed = MeshData{};
  if (!loadAscii(text, parsed, error)) return false;
  out = std::move(parsed);
  return true;
}

}  // namespace brepsight
