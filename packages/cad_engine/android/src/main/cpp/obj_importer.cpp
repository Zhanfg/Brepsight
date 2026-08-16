#include "obj_importer.h"

#include <array>
#include <cmath>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace brepsight {
namespace {

struct FaceIndex {
  int position = 0;
  int uv = 0;
  int normal = 0;
};

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

Vec3 normalize(Vec3 v) {
  const float len2 = v.x * v.x + v.y * v.y + v.z * v.z;
  if (len2 <= 1.0e-20f) return {0.0f, 0.0f, 1.0f};
  const float inv = 1.0f / std::sqrt(len2);
  return {v.x * inv, v.y * inv, v.z * inv};
}

int parseIndexPart(const std::string& value) {
  if (value.empty()) return 0;
  try {
    return std::stoi(value);
  } catch (...) {
    return 0;
  }
}

FaceIndex parseFaceIndex(const std::string& token) {
  FaceIndex out{};
  const auto firstSlash = token.find('/');
  if (firstSlash == std::string::npos) {
    out.position = parseIndexPart(token);
    return out;
  }

  out.position = parseIndexPart(token.substr(0, firstSlash));
  const auto secondSlash = token.find('/', firstSlash + 1);
  if (secondSlash == std::string::npos) {
    out.uv = parseIndexPart(token.substr(firstSlash + 1));
    return out;
  }

  out.uv = parseIndexPart(token.substr(firstSlash + 1, secondSlash - firstSlash - 1));
  out.normal = parseIndexPart(token.substr(secondSlash + 1));
  return out;
}

int resolveIndex(int raw, std::size_t size) {
  if (raw > 0) {
    const int index = raw - 1;
    return index >= 0 && static_cast<std::size_t>(index) < size ? index : -1;
  }
  if (raw < 0) {
    const long long index = static_cast<long long>(size) + raw;
    return index >= 0 && static_cast<std::size_t>(index) < size ? static_cast<int>(index) : -1;
  }
  return -1;
}

bool emitTriangle(
    const std::array<FaceIndex, 3>& face,
    const std::vector<Vec3>& positions,
    const std::vector<Vec2>& uvs,
    const std::vector<Vec3>& normals,
    MeshData& out,
    std::string& error) {
  std::array<int, 3> pIndex{};
  std::array<int, 3> uvIndex{};
  std::array<int, 3> nIndex{};
  std::array<Vec3, 3> p{};

  for (int i = 0; i < 3; ++i) {
    pIndex[static_cast<std::size_t>(i)] = resolveIndex(face[static_cast<std::size_t>(i)].position, positions.size());
    if (pIndex[static_cast<std::size_t>(i)] < 0) {
      error = "OBJ face references an invalid position index.";
      return false;
    }
    p[static_cast<std::size_t>(i)] = positions[static_cast<std::size_t>(pIndex[static_cast<std::size_t>(i)])];
    uvIndex[static_cast<std::size_t>(i)] = resolveIndex(face[static_cast<std::size_t>(i)].uv, uvs.size());
    nIndex[static_cast<std::size_t>(i)] = resolveIndex(face[static_cast<std::size_t>(i)].normal, normals.size());
  }

  const Vec3 faceNormal = normalize(cross(subtract(p[1], p[0]), subtract(p[2], p[0])));
  static constexpr std::array<Vec3, 3> bary = {
      Vec3{1.0f, 0.0f, 0.0f},
      Vec3{0.0f, 1.0f, 0.0f},
      Vec3{0.0f, 0.0f, 1.0f},
  };

  for (int i = 0; i < 3; ++i) {
    const int ni = nIndex[static_cast<std::size_t>(i)];
    const int ti = uvIndex[static_cast<std::size_t>(i)];
    const Vec3 normal = ni >= 0 ? normalize(normals[static_cast<std::size_t>(ni)]) : faceNormal;
    const Vec2 uv = ti >= 0 ? uvs[static_cast<std::size_t>(ti)] : Vec2{};
    out.vertices.push_back({p[static_cast<std::size_t>(i)], normal, bary[static_cast<std::size_t>(i)], uv});
    out.bounds.include(p[static_cast<std::size_t>(i)]);
    out.hasNormals = true;
    if (ti >= 0) out.hasUv = true;
  }
  ++out.triangleCount;
  return true;
}

}  // namespace

bool loadObj(const std::string& path, MeshData& out, std::string& error) {
  std::ifstream file(path);
  if (!file) {
    error = "Unable to open OBJ file.";
    return false;
  }

  std::vector<Vec3> positions;
  std::vector<Vec2> uvs;
  std::vector<Vec3> normals;
  std::string line;
  std::size_t lineNumber = 0;

  while (std::getline(file, line)) {
    ++lineNumber;
    if (line.empty() || line[0] == '#') continue;

    std::istringstream in(line);
    std::string keyword;
    in >> keyword;
    if (keyword.empty()) continue;

    if (keyword == "v") {
      Vec3 p{};
      if (!(in >> p.x >> p.y >> p.z)) {
        error = "Malformed OBJ vertex at line " + std::to_string(lineNumber) + ".";
        return false;
      }
      positions.push_back(p);
    } else if (keyword == "vt") {
      Vec2 uv{};
      if (!(in >> uv.x >> uv.y)) {
        error = "Malformed OBJ texture coordinate at line " + std::to_string(lineNumber) + ".";
        return false;
      }
      uvs.push_back(uv);
    } else if (keyword == "vn") {
      Vec3 n{};
      if (!(in >> n.x >> n.y >> n.z)) {
        error = "Malformed OBJ normal at line " + std::to_string(lineNumber) + ".";
        return false;
      }
      normals.push_back(n);
    } else if (keyword == "f") {
      std::vector<FaceIndex> polygon;
      std::string token;
      while (in >> token) polygon.push_back(parseFaceIndex(token));
      if (polygon.size() < 3) {
        error = "OBJ face has fewer than three vertices at line " + std::to_string(lineNumber) + ".";
        return false;
      }
      for (std::size_t i = 1; i + 1 < polygon.size(); ++i) {
        const std::array<FaceIndex, 3> tri = {polygon[0], polygon[i], polygon[i + 1]};
        if (!emitTriangle(tri, positions, uvs, normals, out, error)) return false;
      }
    }
  }

  if (out.triangleCount == 0) {
    error = "OBJ does not contain any renderable faces.";
    return false;
  }
  out.sourceFormat = "obj";
  return true;
}

}  // namespace brepsight
