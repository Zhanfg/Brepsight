#include "section_filter.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <mutex>
#include <vector>

namespace brepsight {
namespace {

std::mutex gSectionMutex;
SectionPlane gSection;
constexpr float kPlaneEpsilon = 1.0e-6f;

float length(Vec3 value) {
  return std::sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
}

Vec3 normalized(Vec3 value) {
  const float magnitude = length(value);
  if (magnitude <= 1.0e-20f || !std::isfinite(magnitude)) return {};
  return {value.x / magnitude, value.y / magnitude, value.z / magnitude};
}

float signedDistance(const SectionPlane& plane, const Vec3& p) {
  return plane.normal.x * p.x + plane.normal.y * p.y + plane.normal.z * p.z - plane.offset;
}

MeshVertex interpolate(const MeshVertex& a, const MeshVertex& b, float t) {
  auto mix = [t](float av, float bv) { return av + (bv - av) * t; };
  MeshVertex out;
  out.position = {
      mix(a.position.x, b.position.x),
      mix(a.position.y, b.position.y),
      mix(a.position.z, b.position.z),
  };
  out.normal = normalized({
      mix(a.normal.x, b.normal.x),
      mix(a.normal.y, b.normal.y),
      mix(a.normal.z, b.normal.z),
  });
  out.uv = {mix(a.uv.x, b.uv.x), mix(a.uv.y, b.uv.y)};
  return out;
}

std::vector<MeshVertex> clipTriangle(
    const SectionPlane& plane,
    const MeshVertex& a,
    const MeshVertex& b,
    const MeshVertex& c) {
  std::vector<MeshVertex> input{a, b, c};
  std::vector<MeshVertex> output;
  output.reserve(4);
  for (std::size_t i = 0; i < input.size(); ++i) {
    const MeshVertex& current = input[i];
    const MeshVertex& previous = input[(i + input.size() - 1) % input.size()];
    const float dc = signedDistance(plane, current.position);
    const float dp = signedDistance(plane, previous.position);
    const bool currentInside = dc >= -kPlaneEpsilon;
    const bool previousInside = dp >= -kPlaneEpsilon;
    if (currentInside != previousInside) {
      const float denominator = dp - dc;
      const float t = std::abs(denominator) <= 1.0e-20f ? 0.0f : dp / denominator;
      output.push_back(interpolate(previous, current, std::clamp(t, 0.0f, 1.0f)));
    }
    if (currentInside) output.push_back(current);
  }
  return output;
}

Vec3 triangleNormal(const Vec3& a, const Vec3& b, const Vec3& c) {
  const Vec3 u{b.x - a.x, b.y - a.y, b.z - a.z};
  const Vec3 v{c.x - a.x, c.y - a.y, c.z - a.z};
  return normalized({
      u.y * v.z - u.z * v.y,
      u.z * v.x - u.x * v.z,
      u.x * v.y - u.y * v.x,
  });
}

void appendTriangle(
    MeshData& out,
    MeshVertex a,
    MeshVertex b,
    MeshVertex c) {
  const Vec3 faceNormal = triangleNormal(a.position, b.position, c.position);
  a.normal = faceNormal;
  b.normal = faceNormal;
  c.normal = faceNormal;
  a.barycentric = {1.0f, 0.0f, 0.0f};
  b.barycentric = {0.0f, 1.0f, 0.0f};
  c.barycentric = {0.0f, 0.0f, 1.0f};
  out.vertices.push_back(a);
  out.vertices.push_back(b);
  out.vertices.push_back(c);
  out.bounds.include(a.position);
  out.bounds.include(b.position);
  out.bounds.include(c.position);
  ++out.triangleCount;
}

MeshDrawRange clippedRangeTemplate(const MeshDrawRange& source, std::size_t first) {
  MeshDrawRange range = source;
  range.firstVertex = first;
  range.vertexCount = 0;
  return range;
}

bool clipRange(
    const SectionPlane& plane,
    const MeshData& source,
    std::size_t firstVertex,
    std::size_t vertexCount,
    const MeshDrawRange* sourceRange,
    MeshData& out,
    std::string& error) {
  if (firstVertex > source.vertices.size() ||
      vertexCount > source.vertices.size() - firstVertex ||
      vertexCount % 3 != 0) {
    error = "Section plane received a malformed triangle draw range.";
    return false;
  }

  const std::size_t outputFirst = out.vertices.size();
  for (std::size_t offset = 0; offset < vertexCount; offset += 3) {
    const auto polygon = clipTriangle(
        plane,
        source.vertices[firstVertex + offset],
        source.vertices[firstVertex + offset + 1],
        source.vertices[firstVertex + offset + 2]);
    if (polygon.size() < 3) continue;
    for (std::size_t index = 1; index + 1 < polygon.size(); ++index) {
      appendTriangle(out, polygon[0], polygon[index], polygon[index + 1]);
    }
  }

  if (sourceRange != nullptr && out.vertices.size() > outputFirst) {
    MeshDrawRange range = clippedRangeTemplate(*sourceRange, outputFirst);
    range.vertexCount = out.vertices.size() - outputFirst;
    out.drawRanges.push_back(std::move(range));
  }
  return true;
}

}  // namespace

bool setActiveSectionPlane(
    bool enabled,
    Vec3 normal,
    float offset,
    std::string& error) {
  if (!std::isfinite(offset) || !std::isfinite(normal.x) ||
      !std::isfinite(normal.y) || !std::isfinite(normal.z)) {
    error = "Section plane values must be finite.";
    return false;
  }
  const Vec3 unit = normalized(normal);
  if (enabled && length(unit) <= 1.0e-20f) {
    error = "Section plane normal must be non-zero.";
    return false;
  }
  std::lock_guard lock(gSectionMutex);
  gSection.enabled = enabled;
  gSection.normal = enabled ? unit : Vec3{0.0f, 0.0f, 1.0f};
  gSection.offset = offset;
  error.clear();
  return true;
}

SectionPlane activeSectionPlane() {
  std::lock_guard lock(gSectionMutex);
  return gSection;
}

bool applyActiveSectionPlane(MeshData& mesh, std::string& error) {
  const SectionPlane plane = activeSectionPlane();
  if (!plane.enabled || mesh.vertices.empty()) {
    error.clear();
    return true;
  }

  MeshData clipped;
  clipped.sourceFormat = mesh.sourceFormat;
  clipped.hasNormals = true;
  clipped.hasUv = mesh.hasUv;
  clipped.objectPresentation = mesh.objectPresentation;

  if (mesh.drawRanges.empty()) {
    if (!clipRange(plane, mesh, 0, mesh.vertices.size(), nullptr, clipped, error)) return false;
  } else {
    for (const MeshDrawRange& range : mesh.drawRanges) {
      if (!clipRange(
              plane,
              mesh,
              range.firstVertex,
              range.vertexCount,
              &range,
              clipped,
              error)) {
        return false;
      }
    }
  }

  mesh.vertices = std::move(clipped.vertices);
  mesh.drawRanges = std::move(clipped.drawRanges);
  mesh.bounds = clipped.bounds;
  mesh.triangleCount = clipped.triangleCount;
  mesh.hasNormals = clipped.hasNormals;
  mesh.hasUv = clipped.hasUv;
  error.clear();
  return true;
}

}  // namespace brepsight
