#include "mesh_components.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <numeric>
#include <unordered_map>
#include <utility>
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

std::vector<MeshData> splitConnectedComponents(const MeshData& mesh) {
  const std::size_t triangleCount = std::min(
      mesh.triangleCount,
      mesh.vertices.size() / static_cast<std::size_t>(3));
  if (triangleCount == 0) return {};

  const double extent = std::max(static_cast<double>(mesh.bounds.maxExtent()), 1.0e-6);
  const double weldTolerance = std::max(extent * 1.0e-6, 1.0e-7);
  const double inverseTolerance = 1.0 / weldTolerance;

  std::unordered_map<QuantizedPoint, std::size_t, QuantizedPointHash> weldedLookup;
  weldedLookup.reserve(triangleCount * static_cast<std::size_t>(2));
  std::vector<std::size_t> weldedIndices(triangleCount * static_cast<std::size_t>(3));
  for (std::size_t i = 0; i < weldedIndices.size(); ++i) {
    const QuantizedPoint key = quantize(mesh.vertices[i].position, inverseTolerance);
    const auto [it, inserted] = weldedLookup.emplace(key, weldedLookup.size());
    weldedIndices[i] = it->second;
    (void)inserted;
  }

  std::unordered_map<EdgeKey, std::size_t, EdgeKeyHash> firstTriangleByEdge;
  firstTriangleByEdge.reserve(triangleCount * static_cast<std::size_t>(3));
  DisjointSet components(triangleCount);

  for (std::size_t triangle = 0; triangle < triangleCount; ++triangle) {
    const std::size_t base = triangle * static_cast<std::size_t>(3);
    const std::array<std::size_t, 3> ids = {
        weldedIndices[base],
        weldedIndices[base + 1],
        weldedIndices[base + 2],
    };
    const std::array<EdgeKey, 3> edges = {
        edgeKey(ids[0], ids[1]),
        edgeKey(ids[1], ids[2]),
        edgeKey(ids[2], ids[0]),
    };
    for (const EdgeKey& edge : edges) {
      const auto [it, inserted] = firstTriangleByEdge.emplace(edge, triangle);
      if (!inserted) components.unite(triangle, it->second);
    }
  }

  std::unordered_map<std::size_t, std::size_t> rootToOutput;
  std::vector<MeshData> output;
  for (std::size_t triangle = 0; triangle < triangleCount; ++triangle) {
    const std::size_t root = components.find(triangle);
    auto [it, inserted] = rootToOutput.emplace(root, output.size());
    if (inserted) {
      MeshData component;
      component.hasNormals = mesh.hasNormals;
      component.hasUv = mesh.hasUv;
      component.sourceFormat = mesh.sourceFormat;
      output.push_back(std::move(component));
    }

    MeshData& component = output[it->second];
    const std::size_t base = triangle * static_cast<std::size_t>(3);
    for (std::size_t i = 0; i < 3; ++i) {
      const MeshVertex& vertex = mesh.vertices[base + i];
      component.vertices.push_back(vertex);
      component.bounds.include(vertex.position);
    }
    ++component.triangleCount;
  }

  std::sort(output.begin(), output.end(), [](const MeshData& a, const MeshData& b) {
    return a.triangleCount > b.triangleCount;
  });
  return output;
}

}  // namespace brepsight
