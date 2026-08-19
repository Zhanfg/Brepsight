#include "mesh_transform.h"

#include <cmath>

namespace brepsight {
namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr float kScaleEpsilon = 1.0e-6f;
constexpr float kNormalEpsilon = 1.0e-12f;

bool finite(float value) {
  return std::isfinite(value);
}

bool finite(const Vec3& value) {
  return finite(value.x) && finite(value.y) && finite(value.z);
}

Vec3 rotateX(const Vec3& value, float radians) {
  const float c = std::cos(radians);
  const float s = std::sin(radians);
  return {value.x, value.y * c - value.z * s, value.y * s + value.z * c};
}

Vec3 rotateY(const Vec3& value, float radians) {
  const float c = std::cos(radians);
  const float s = std::sin(radians);
  return {value.x * c + value.z * s, value.y, -value.x * s + value.z * c};
}

Vec3 rotateZ(const Vec3& value, float radians) {
  const float c = std::cos(radians);
  const float s = std::sin(radians);
  return {value.x * c - value.y * s, value.x * s + value.y * c, value.z};
}

Vec3 rotate(const Vec3& value, const Vec3& radians) {
  return rotateZ(rotateY(rotateX(value, radians.x), radians.y), radians.z);
}

Vec3 normalized(const Vec3& value) {
  const float lengthSquared = value.x * value.x + value.y * value.y + value.z * value.z;
  if (!finite(lengthSquared) || lengthSquared <= kNormalEpsilon) return {};
  const float inverseLength = 1.0f / std::sqrt(lengthSquared);
  return {value.x * inverseLength, value.y * inverseLength, value.z * inverseLength};
}

Bounds3 boundsFromVertices(const MeshData& mesh) {
  Bounds3 bounds;
  for (const MeshVertex& vertex : mesh.vertices) bounds.include(vertex.position);
  return bounds;
}

}  // namespace

bool applyMeshTransform(MeshData& mesh, const MeshTransform& transform, std::string& error) {
  error.clear();
  if (mesh.vertices.empty()) {
    error = "Mesh transform requires at least one vertex.";
    return false;
  }
  if (!finite(transform.translation) || !finite(transform.rotationDegrees) || !finite(transform.scale)) {
    error = "Mesh transform contains a non-finite value.";
    return false;
  }
  if (transform.scale.x <= kScaleEpsilon ||
      transform.scale.y <= kScaleEpsilon ||
      transform.scale.z <= kScaleEpsilon) {
    error = "Mesh scale must be positive and non-zero.";
    return false;
  }

  Bounds3 sourceBounds = mesh.bounds.valid ? mesh.bounds : boundsFromVertices(mesh);
  if (!sourceBounds.valid) {
    error = "Mesh transform could not determine source bounds.";
    return false;
  }
  const Vec3 center = sourceBounds.center();
  const Vec3 radians{
      std::remainder(transform.rotationDegrees.x, 360.0f) * kPi / 180.0f,
      std::remainder(transform.rotationDegrees.y, 360.0f) * kPi / 180.0f,
      std::remainder(transform.rotationDegrees.z, 360.0f) * kPi / 180.0f,
  };

  Bounds3 transformedBounds;
  for (MeshVertex& vertex : mesh.vertices) {
    const Vec3 centered{
        vertex.position.x - center.x,
        vertex.position.y - center.y,
        vertex.position.z - center.z,
    };
    const Vec3 scaled{
        centered.x * transform.scale.x,
        centered.y * transform.scale.y,
        centered.z * transform.scale.z,
    };
    const Vec3 rotated = rotate(scaled, radians);
    vertex.position = {
        rotated.x + center.x + transform.translation.x,
        rotated.y + center.y + transform.translation.y,
        rotated.z + center.z + transform.translation.z,
    };
    if (!finite(vertex.position)) {
      error = "Mesh transform produced a non-finite vertex.";
      return false;
    }
    transformedBounds.include(vertex.position);

    if (mesh.hasNormals) {
      // For M = R*S, normal transform is R*inverse(S)^T.
      const Vec3 inverseScaledNormal{
          vertex.normal.x / transform.scale.x,
          vertex.normal.y / transform.scale.y,
          vertex.normal.z / transform.scale.z,
      };
      vertex.normal = normalized(rotate(inverseScaledNormal, radians));
    }
  }

  mesh.bounds = transformedBounds;
  return true;
}

}  // namespace brepsight
