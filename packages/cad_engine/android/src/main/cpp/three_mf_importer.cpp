#include "three_mf_importer.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <unordered_set>
#include <utility>
#include <vector>

#if defined(BREPSIGHT_WITH_LIB3MF)
#include <lib3mf_implicit.hpp>
#endif

namespace brepsight {

#if defined(BREPSIGHT_WITH_LIB3MF)
namespace {

constexpr std::size_t kMaxHierarchyDepth = 64;
constexpr std::size_t kMaxExpandedObjects = 1000000;
constexpr std::size_t kMaxExpandedTriangles = 5000000;

struct Mat4 {
  float m[4][4]{};
};

Mat4 identityMatrix() {
  Mat4 result{};
  for (int i = 0; i < 4; ++i) result.m[i][i] = 1.0f;
  return result;
}

Mat4 matrixFromLib3Mf(const Lib3MF::sTransform& transform) {
  Mat4 result{};
  for (int row = 0; row < 4; ++row) {
    for (int column = 0; column < 3; ++column) {
      result.m[row][column] = transform.m_Fields[row][column];
    }
  }
  result.m[3][3] = 1.0f;
  return result;
}

Mat4 multiply(const Mat4& left, const Mat4& right) {
  Mat4 result{};
  for (int row = 0; row < 4; ++row) {
    for (int column = 0; column < 4; ++column) {
      for (int k = 0; k < 4; ++k) {
        result.m[row][column] += left.m[row][k] * right.m[k][column];
      }
    }
  }
  return result;
}

Vec3 transformPoint(const Mat4& matrix, const Lib3MF::sPosition& source, float unitScaleMm) {
  const float x = source.m_Coordinates[0];
  const float y = source.m_Coordinates[1];
  const float z = source.m_Coordinates[2];
  return {
      (x * matrix.m[0][0] + y * matrix.m[1][0] + z * matrix.m[2][0] + matrix.m[3][0]) * unitScaleMm,
      (x * matrix.m[0][1] + y * matrix.m[1][1] + z * matrix.m[2][1] + matrix.m[3][1]) * unitScaleMm,
      (x * matrix.m[0][2] + y * matrix.m[1][2] + z * matrix.m[2][2] + matrix.m[3][2]) * unitScaleMm,
  };
}

float determinant3x3(const Mat4& matrix) {
  const float a = matrix.m[0][0];
  const float b = matrix.m[0][1];
  const float c = matrix.m[0][2];
  const float d = matrix.m[1][0];
  const float e = matrix.m[1][1];
  const float f = matrix.m[1][2];
  const float g = matrix.m[2][0];
  const float h = matrix.m[2][1];
  const float i = matrix.m[2][2];
  return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
}

Vec3 subtract(const Vec3& left, const Vec3& right) {
  return {left.x - right.x, left.y - right.y, left.z - right.z};
}

Vec3 cross(const Vec3& left, const Vec3& right) {
  return {
      left.y * right.z - left.z * right.y,
      left.z * right.x - left.x * right.z,
      left.x * right.y - left.y * right.x,
  };
}

Vec3 normalize(const Vec3& value) {
  const float lengthSquared = value.x * value.x + value.y * value.y + value.z * value.z;
  if (lengthSquared <= 1.0e-20f) return {0.0f, 0.0f, 1.0f};
  const float inverseLength = 1.0f / std::sqrt(lengthSquared);
  return {value.x * inverseLength, value.y * inverseLength, value.z * inverseLength};
}

std::string unitName(Lib3MF::eModelUnit unit) {
  switch (unit) {
    case Lib3MF::eModelUnit::MicroMeter: return "micron";
    case Lib3MF::eModelUnit::MilliMeter: return "millimeter";
    case Lib3MF::eModelUnit::CentiMeter: return "centimeter";
    case Lib3MF::eModelUnit::Inch: return "inch";
    case Lib3MF::eModelUnit::Foot: return "foot";
    case Lib3MF::eModelUnit::Meter: return "meter";
  }
  return "unknown";
}

float unitScaleToMillimeters(Lib3MF::eModelUnit unit) {
  switch (unit) {
    case Lib3MF::eModelUnit::MicroMeter: return 0.001f;
    case Lib3MF::eModelUnit::MilliMeter: return 1.0f;
    case Lib3MF::eModelUnit::CentiMeter: return 10.0f;
    case Lib3MF::eModelUnit::Inch: return 25.4f;
    case Lib3MF::eModelUnit::Foot: return 304.8f;
    case Lib3MF::eModelUnit::Meter: return 1000.0f;
  }
  throw std::runtime_error("Unsupported 3MF model unit.");
}

std::array<float, 12> copyTransform(const Lib3MF::sTransform& transform) {
  std::array<float, 12> result{};
  std::size_t index = 0;
  for (int row = 0; row < 4; ++row) {
    for (int column = 0; column < 3; ++column) {
      result[index++] = transform.m_Fields[row][column];
    }
  }
  return result;
}

void appendTriangle(
    const Vec3& first,
    const Vec3& second,
    const Vec3& third,
    MeshData& output) {
  const Vec3 normal = normalize(cross(subtract(second, first), subtract(third, first)));

  MeshVertex a{};
  a.position = first;
  a.normal = normal;
  a.barycentric = {1.0f, 0.0f, 0.0f};

  MeshVertex b{};
  b.position = second;
  b.normal = normal;
  b.barycentric = {0.0f, 1.0f, 0.0f};

  MeshVertex c{};
  c.position = third;
  c.normal = normal;
  c.barycentric = {0.0f, 0.0f, 1.0f};

  output.vertices.push_back(a);
  output.vertices.push_back(b);
  output.vertices.push_back(c);
  output.bounds.include(first);
  output.bounds.include(second);
  output.bounds.include(third);
  ++output.triangleCount;
}

void appendMeshObject(
    const Lib3MF::PModel& model,
    std::uint32_t resourceId,
    const Mat4& worldTransform,
    float unitScaleMm,
    MeshData& output) {
  auto mesh = model->GetMeshObjectByID(resourceId);
  if (!mesh) throw std::runtime_error("3MF mesh object lookup returned null.");

  const auto triangleCount = static_cast<std::size_t>(mesh->GetTriangleCount());
  if (triangleCount > kMaxExpandedTriangles - output.triangleCount) {
    throw std::runtime_error("3MF expanded triangle limit exceeded.");
  }

  std::vector<Lib3MF::sPosition> positions;
  std::vector<Lib3MF::sTriangle> triangles;
  mesh->GetVertices(positions);
  mesh->GetTriangleIndices(triangles);

  const bool mirrored = determinant3x3(worldTransform) < 0.0f;
  for (const auto& triangle : triangles) {
    std::uint32_t indices[3] = {
        triangle.m_Indices[0],
        triangle.m_Indices[1],
        triangle.m_Indices[2],
    };
    if (mirrored) std::swap(indices[1], indices[2]);
    if (indices[0] >= positions.size() || indices[1] >= positions.size() || indices[2] >= positions.size()) {
      throw std::runtime_error("3MF triangle references a vertex outside its mesh.");
    }

    appendTriangle(
        transformPoint(worldTransform, positions[indices[0]], unitScaleMm),
        transformPoint(worldTransform, positions[indices[1]], unitScaleMm),
        transformPoint(worldTransform, positions[indices[2]], unitScaleMm),
        output);
  }
}

void appendObjectRecursive(
    const Lib3MF::PModel& model,
    const Lib3MF::PObject& object,
    const Mat4& worldTransform,
    float unitScaleMm,
    MeshData& output,
    ThreeMfPayload& payload,
    std::unordered_set<std::uint32_t>& recursionPath,
    std::size_t depth) {
  if (!object) throw std::runtime_error("3MF object resource lookup returned null.");
  if (depth > kMaxHierarchyDepth) throw std::runtime_error("3MF component nesting limit exceeded.");
  if (payload.expandedObjectCount >= kMaxExpandedObjects) {
    throw std::runtime_error("3MF expanded object limit exceeded.");
  }

  const std::uint32_t resourceId = object->GetResourceID();
  if (!recursionPath.insert(resourceId).second) {
    throw std::runtime_error("Cyclic 3MF component reference rejected.");
  }
  ++payload.expandedObjectCount;

  if (object->IsMeshObject()) {
    appendMeshObject(model, resourceId, worldTransform, unitScaleMm, output);
    recursionPath.erase(resourceId);
    return;
  }

  if (object->IsComponentsObject()) {
    auto componentsObject = model->GetComponentsObjectByID(resourceId);
    const auto componentCount = componentsObject->GetComponentCount();
    for (Lib3MF_uint32 index = 0; index < componentCount; ++index) {
      auto component = componentsObject->GetComponent(index);
      auto child = component->GetObjectResource();
      const Mat4 localTransform = component->HasTransform()
          ? matrixFromLib3Mf(component->GetTransform())
          : identityMatrix();
      appendObjectRecursive(
          model,
          child,
          multiply(localTransform, worldTransform),
          unitScaleMm,
          output,
          payload,
          recursionPath,
          depth + 1);
    }
    recursionPath.erase(resourceId);
    return;
  }

  recursionPath.erase(resourceId);
  throw std::runtime_error("3MF object type is not supported by the core mesh/components provider yet.");
}

}  // namespace
#endif

ThreeMfImportResult importThreeMf(const std::string& path) {
  ThreeMfImportResult result;

#if !defined(BREPSIGHT_WITH_LIB3MF)
  (void)path;
  result.error = "3MF provider is not linked into this build.";
  return result;
#else
  try {
    auto wrapper = Lib3MF::CWrapper::loadLibrary();
    auto model = wrapper->CreateModel();
    auto reader = model->QueryReader("3mf");
    reader->SetStrictModeActive(true);
    reader->ReadFromFile(path);

    auto payload = std::make_shared<ThreeMfPayload>();
    const auto unit = model->GetUnit();
    payload->modelUnit = unitName(unit);
    const float unitScaleMm = unitScaleToMillimeters(unit);

    auto mesh = std::make_shared<MeshData>();
    mesh->sourceFormat = "3mf";
    mesh->hasNormals = true;
    mesh->hasUv = false;

    auto buildItems = model->GetBuildItems();
    while (buildItems->MoveNext()) {
      auto item = buildItems->GetCurrent();
      auto object = item->GetObjectResource();

      ThreeMfBuildItemInfo info{};
      info.resourceId = item->GetObjectResourceID();
      info.name = object->GetName();
      info.partNumber = item->GetPartNumber();
      if (info.partNumber.empty()) info.partNumber = object->GetPartNumber();
      info.meshObject = object->IsMeshObject();
      info.componentsObject = object->IsComponentsObject();

      const Lib3MF::sTransform transform = item->HasObjectTransform()
          ? item->GetObjectTransform()
          : wrapper->GetIdentityTransform();
      info.transform = copyTransform(transform);
      payload->buildItems.push_back(std::move(info));
      ++result.rootObjectCount;

      std::unordered_set<std::uint32_t> recursionPath;
      appendObjectRecursive(
          model,
          object,
          matrixFromLib3Mf(transform),
          unitScaleMm,
          *mesh,
          *payload,
          recursionPath,
          0);
    }

    if (result.rootObjectCount == 0) {
      result.error = "3MF model contains no build items.";
      return result;
    }
    if (mesh->vertices.empty()) {
      result.error = "3MF build produced no supported mesh triangles.";
      return result;
    }

    result.hierarchyNodeCount = payload->expandedObjectCount;
    result.displayMesh = std::move(mesh);
    result.payload = std::move(payload);
    return result;
  } catch (const Lib3MF::ELib3MFException& exception) {
    result.error = std::string("lib3mf import failed: ") + exception.what();
    return result;
  } catch (const std::exception& exception) {
    result.error = std::string("3MF import failed: ") + exception.what();
    return result;
  }
#endif
}

}  // namespace brepsight
