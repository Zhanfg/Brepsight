#pragma once

#include <algorithm>
#include <cstddef>
#include <limits>
#include <string>
#include <vector>

namespace brepsight {

struct Vec3 {
  float x = 0.0f;
  float y = 0.0f;
  float z = 0.0f;
};

struct MeshVertex {
  Vec3 position;
  Vec3 normal;
  Vec3 barycentric;
};

struct Bounds3 {
  Vec3 min{
      std::numeric_limits<float>::max(),
      std::numeric_limits<float>::max(),
      std::numeric_limits<float>::max()};
  Vec3 max{
      std::numeric_limits<float>::lowest(),
      std::numeric_limits<float>::lowest(),
      std::numeric_limits<float>::lowest()};
  bool valid = false;

  void include(const Vec3& p) {
    min.x = std::min(min.x, p.x);
    min.y = std::min(min.y, p.y);
    min.z = std::min(min.z, p.z);
    max.x = std::max(max.x, p.x);
    max.y = std::max(max.y, p.y);
    max.z = std::max(max.z, p.z);
    valid = true;
  }

  Vec3 center() const {
    if (!valid) return {};
    return {
        (min.x + max.x) * 0.5f,
        (min.y + max.y) * 0.5f,
        (min.z + max.z) * 0.5f,
    };
  }

  float maxExtent() const {
    if (!valid) return 1.0f;
    return std::max({max.x - min.x, max.y - min.y, max.z - min.z, 1.0e-6f});
  }
};

struct MeshData {
  std::vector<MeshVertex> vertices;
  Bounds3 bounds;
  std::size_t triangleCount = 0;
  std::string sourceFormat;
};

}  // namespace brepsight
