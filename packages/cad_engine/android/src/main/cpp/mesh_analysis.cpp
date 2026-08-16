#include "mesh_analysis.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <numeric>
#include <unordered_map>
#include <vector>

namespace brepsight {
namespace {

struct QuantizedPoint {
  int64_t x = 0;
  int64_t y = 0;
  int64_t z = 0;

  bool operator==(const QuantizedPoint& other) const {
    return x == other.x && y == other.y && z == other.z;
  }
};

struct QuantizedPointHash {
  std::size_t operator()(const QuantizedPoint& p) const noexcept {
    std::size_t h = std::hash<int64_t>{}(p.x);
    h ^= std::hash<int64_t>{}(p.y) + 0x9e3779b9U + (h << 6U) + (h >> 2U);
    h ^= std::hash<int64_t>{}(p.z) + 0x9e3779b9U + (h << 6U) + (h >> 2U);
    return h;
  }
};

struct EdgeKey {
  std::size_t a = 0;
  std::size_t b = 0;

  bool operator==(const EdgeKey& other) const {
    return a == other.a && b == other.b;
  }
};

struct EdgeKeyHash {
  std::size_t operator()(const EdgeKey& edge) const noexcept {
    std::size_t h = std::hash<std::size_t>{}(edge.a);
    h ^= std::hash<std::size_t>{}(edge.b) + 0x9e3779b9U + (h << 6U) + (h >> 2U);
    return h;
  }
};

class DisjointSet {
 public:
  explicit DisjointSet(std::size_t count) : parent_(count), rank_(count, 0) {
    std::iota(parent_.begin(), parent_.end(), 0);
  }

  std::size_t find(std::size_t value) {
    if (parent_[value] != value) parent_[value] = find(parent_[value]);
    return parent_[value];
  }

  void unite(std::size_t a, std::size_t b) {
    a = find(a);
    b = find(b);
    if (a == b) return;
    if (rank_[a] < rank_[b]) std::swap(a, b);
    parent_[b] = a;
    if (rank_[a] == rank_[b]) ++rank_[a];
  }

 private:
  std::vector<std::size_t> parent_;
  std::vector<unsigned char> rank_;
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

double length(const Vec3& v) {
  return std::sqrt(
      static_cast<double>(v.x) * v.x +
      static_cast<double>(v.y) * v.y +
      static_cast<double>(v.z) * v.z);
}

double signedTetrahedronVolume(const Vec3& a, const Vec3& b, const Vec3& c) {
  return (
      static_cast<double>(a.x) * (static_cast<double>(b.y) * c.z - static_cast<double>(b.z) * c.y) -
      static_cast<double>(a.y) * (static_cast<double>(b.x) * c.z - static_cast<double>(b.z) * c.x) +
      static_cast<double>(a.z) * (static_cast<double>(b.x) * c.y - static_cast<double>(b.y) * c.x)) / 6.0;
}

QuantizedPoint quantize(const Vec3& p, double inverseTolerance) {
  return {
      static_cast<int64_t>(std::llround(static_cast<double>(p.x) * inverseTolerance)),
      static_cast<int64_t>(std::llround(static_cast<double>(p.y) * inverseTolerance)),
      static_cast<int64_t>(std::llround(static_cast<double>(p.z) * inverseTolerance)),
  };
}

EdgeKey edgeKey(std::size_t a, std::size_t b) {
  return a < b ? EdgeKey{a, b} : EdgeKey{b, a};
}

}  // namespace

MeshAnalysis analyzeMesh(const MeshData& mesh) {
  MeshAnalysis result;
  result.bounds = mesh.bounds;
  result.triangleCount = std::min(
      mesh.triangleCount,
      mesh.vertices.size() / static_cast<std::size_t>(3));
  if (result.triangleCount == 0) return result;

  const double extent = std::max(static_cast<double>(mesh.bounds.maxExtent()), 1.0e-6);
  const double weldTolerance = std::max(extent * 1.0e-6, 1.0e-7);
  const double inverseTolerance = 1.0 / weldTolerance;
  const double areaEpsilon = weldTolerance * weldTolerance * 0.25;

  std::unordered_map<QuantizedPoint, std::size_t, QuantizedPointHash> weldedLookup;
  weldedLookup.reserve(result.triangleCount * static_cast<std::size_t>(2));
  std::vector<std::size_t> weldedIndices(result.triangleCount * static_cast<std::size_t>(3));

  for (std::size_t i = 0; i < weldedIndices.size(); ++i) {
    const QuantizedPoint key = quantize(mesh.vertices[i].position, inverseTolerance);
    const auto [it, inserted] = weldedLookup.emplace(key, weldedLookup.size());
    weldedIndices[i] = it->second;
    (void)inserted;
  }
  result.uniqueVertexCount = weldedLookup.size();

  struct EdgeUse {
    std::size_t count = 0;
    std::size_t firstTriangle = 0;
  };
  std::unordered_map<EdgeKey, EdgeUse, EdgeKeyHash> edges;
  edges.reserve(result.triangleCount * static_cast<std::size_t>(3));
  DisjointSet components(result.triangleCount);
  double signedVolume = 0.0;

  for (std::size_t triangle = 0; triangle < result.triangleCount; ++triangle) {
    const std::size_t base = triangle * static_cast<std::size_t>(3);
    const Vec3& a = mesh.vertices[base + 0].position;
    const Vec3& b = mesh.vertices[base + 1].position;
    const Vec3& c = mesh.vertices[base + 2].position;
    const Vec3 crossValue = cross(subtract(b, a), subtract(c, a));
    const double doubledArea = length(crossValue);
    const double area = doubledArea * 0.5;
    result.surfaceArea += area;
    signedVolume += signedTetrahedronVolume(a, b, c);
    if (area <= areaEpsilon) ++result.degenerateTriangleCount;

    const std::array<std::size_t, 3> ids = {
        weldedIndices[base + 0],
        weldedIndices[base + 1],
        weldedIndices[base + 2],
    };
    const std::array<EdgeKey, 3> triangleEdges = {
        edgeKey(ids[0], ids[1]),
        edgeKey(ids[1], ids[2]),
        edgeKey(ids[2], ids[0]),
    };

    for (const EdgeKey& edge : triangleEdges) {
      auto [it, inserted] = edges.emplace(edge, EdgeUse{1, triangle});
      if (!inserted) {
        ++it->second.count;
        components.unite(triangle, it->second.firstTriangle);
      }
    }
  }

  for (const auto& [edge, use] : edges) {
    (void)edge;
    if (use.count == 1) ++result.openEdgeCount;
    if (use.count > 2) ++result.nonManifoldEdgeCount;
  }

  std::size_t componentCount = 0;
  for (std::size_t triangle = 0; triangle < result.triangleCount; ++triangle) {
    if (components.find(triangle) == triangle) ++componentCount;
  }
  result.connectedComponentCount = componentCount;
  result.closed = result.openEdgeCount == 0 &&
                  result.nonManifoldEdgeCount == 0 &&
                  result.degenerateTriangleCount == 0;
  result.enclosedVolume = result.closed ? std::abs(signedVolume) : 0.0;
  return result;
}

}  // namespace brepsight
