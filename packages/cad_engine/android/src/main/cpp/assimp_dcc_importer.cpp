#include "assimp_dcc_importer.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "mesh_presentation.h"

#if defined(BREPSIGHT_WITH_ASSIMP)
#include <assimp/Importer.hpp>
#include <assimp/material.h>
#include <assimp/postprocess.h>
#include <assimp/scene.h>
#endif

namespace brepsight {

#if defined(BREPSIGHT_WITH_ASSIMP)
namespace {

constexpr std::size_t kMaxHierarchyDepth = 512;
constexpr std::size_t kMaxNodes = 250000;
constexpr std::size_t kMaxOutputVertices = 6000000;
constexpr std::size_t kMaxMaterials = 100000;

struct Matrix4 {
  std::array<double, 16> m{
      1.0, 0.0, 0.0, 0.0,
      0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0,
  };
};

Matrix4 fromAssimp(const aiMatrix4x4& value) {
  return {{
      static_cast<double>(value.a1), static_cast<double>(value.a2),
      static_cast<double>(value.a3), static_cast<double>(value.a4),
      static_cast<double>(value.b1), static_cast<double>(value.b2),
      static_cast<double>(value.b3), static_cast<double>(value.b4),
      static_cast<double>(value.c1), static_cast<double>(value.c2),
      static_cast<double>(value.c3), static_cast<double>(value.c4),
      static_cast<double>(value.d1), static_cast<double>(value.d2),
      static_cast<double>(value.d3), static_cast<double>(value.d4),
  }};
}

Matrix4 multiply(const Matrix4& left, const Matrix4& right) {
  Matrix4 out;
  out.m.fill(0.0);
  for (std::size_t row = 0; row < 4; ++row) {
    for (std::size_t column = 0; column < 4; ++column) {
      for (std::size_t k = 0; k < 4; ++k) {
        out.m[row * 4 + column] +=
            left.m[row * 4 + k] * right.m[k * 4 + column];
      }
    }
  }
  return out;
}

bool finiteMatrix(const Matrix4& matrix) {
  return std::all_of(matrix.m.begin(), matrix.m.end(), [](double value) {
    return std::isfinite(value);
  });
}

Vec3 transformPoint(const Matrix4& matrix, const aiVector3D& point) {
  const double x = matrix.m[0] * point.x + matrix.m[1] * point.y +
      matrix.m[2] * point.z + matrix.m[3];
  const double y = matrix.m[4] * point.x + matrix.m[5] * point.y +
      matrix.m[6] * point.z + matrix.m[7];
  const double z = matrix.m[8] * point.x + matrix.m[9] * point.y +
      matrix.m[10] * point.z + matrix.m[11];
  return {
      static_cast<float>(x),
      static_cast<float>(y),
      static_cast<float>(z),
  };
}

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

Vec3 normalize(Vec3 value) {
  const double lengthSquared = static_cast<double>(value.x) * value.x +
      static_cast<double>(value.y) * value.y +
      static_cast<double>(value.z) * value.z;
  if (!std::isfinite(lengthSquared) || lengthSquared <= 1.0e-24) {
    return {0.0f, 0.0f, 1.0f};
  }
  const double scale = 1.0 / std::sqrt(lengthSquared);
  return {
      static_cast<float>(value.x * scale),
      static_cast<float>(value.y * scale),
      static_cast<float>(value.z * scale),
  };
}

Vec3 transformNormal(const Matrix4& matrix, const aiVector3D& normal, bool& approximate) {
  const double a00 = matrix.m[0];
  const double a01 = matrix.m[1];
  const double a02 = matrix.m[2];
  const double a10 = matrix.m[4];
  const double a11 = matrix.m[5];
  const double a12 = matrix.m[6];
  const double a20 = matrix.m[8];
  const double a21 = matrix.m[9];
  const double a22 = matrix.m[10];

  const double c00 = a11 * a22 - a12 * a21;
  const double c01 = a12 * a20 - a10 * a22;
  const double c02 = a10 * a21 - a11 * a20;
  const double c10 = a02 * a21 - a01 * a22;
  const double c11 = a00 * a22 - a02 * a20;
  const double c12 = a01 * a20 - a00 * a21;
  const double c20 = a01 * a12 - a02 * a11;
  const double c21 = a02 * a10 - a00 * a12;
  const double c22 = a00 * a11 - a01 * a10;
  const double determinant = a00 * c00 + a01 * c01 + a02 * c02;

  if (!std::isfinite(determinant) || std::fabs(determinant) <= 1.0e-18) {
    approximate = true;
    return normalize({
        static_cast<float>(a00 * normal.x + a01 * normal.y + a02 * normal.z),
        static_cast<float>(a10 * normal.x + a11 * normal.y + a12 * normal.z),
        static_cast<float>(a20 * normal.x + a21 * normal.y + a22 * normal.z),
    });
  }

  const double inverseDeterminant = 1.0 / determinant;
  return normalize({
      static_cast<float>((c00 * normal.x + c01 * normal.y + c02 * normal.z) * inverseDeterminant),
      static_cast<float>((c10 * normal.x + c11 * normal.y + c12 * normal.z) * inverseDeterminant),
      static_cast<float>((c20 * normal.x + c21 * normal.y + c22 * normal.z) * inverseDeterminant),
  });
}

std::string nodeIdFor(const std::string& parentId, unsigned int childIndex) {
  return parentId.empty()
      ? "n0"
      : parentId + "/" + std::to_string(childIndex);
}

std::array<double, 16> transformArray(const Matrix4& matrix) {
  return matrix.m;
}

bool appendAssimpMesh(
    const aiScene& scene,
    const aiMesh& source,
    const Matrix4& world,
    const std::string& nodeId,
    MeshData& destination,
    AssimpDccPayload& payload,
    bool& approximateNormals,
    std::size_t& skippedFaces,
    std::string& error) {
  const std::size_t firstVertex = destination.vertices.size();
  static constexpr std::array<Vec3, 3> barycentric = {
      Vec3{1.0f, 0.0f, 0.0f},
      Vec3{0.0f, 1.0f, 0.0f},
      Vec3{0.0f, 0.0f, 1.0f},
  };

  for (unsigned int faceIndex = 0; faceIndex < source.mNumFaces; ++faceIndex) {
    const aiFace& face = source.mFaces[faceIndex];
    if (face.mNumIndices != 3) {
      ++skippedFaces;
      continue;
    }
    if (destination.vertices.size() > kMaxOutputVertices - 3) {
      error = "Assimp display mesh exceeds the mobile vertex safety limit.";
      return false;
    }

    std::array<Vec3, 3> positions{};
    for (std::size_t corner = 0; corner < 3; ++corner) {
      const unsigned int sourceIndex = face.mIndices[corner];
      if (sourceIndex >= source.mNumVertices) {
        error = "Assimp mesh face references an invalid vertex index.";
        return false;
      }
      positions[corner] = transformPoint(world, source.mVertices[sourceIndex]);
      if (!std::isfinite(positions[corner].x) ||
          !std::isfinite(positions[corner].y) ||
          !std::isfinite(positions[corner].z)) {
        error = "Assimp node transform produced a non-finite position.";
        return false;
      }
    }

    const Vec3 faceNormal = normalize(cross(
        subtract(positions[1], positions[0]),
        subtract(positions[2], positions[0])));

    for (std::size_t corner = 0; corner < 3; ++corner) {
      const unsigned int sourceIndex = face.mIndices[corner];
      const Vec3 normal = source.HasNormals()
          ? transformNormal(world, source.mNormals[sourceIndex], approximateNormals)
          : faceNormal;
      Vec2 uv{};
      if (source.HasTextureCoords(0)) {
        uv = {source.mTextureCoords[0][sourceIndex].x, source.mTextureCoords[0][sourceIndex].y};
        destination.hasUv = true;
      }
      destination.vertices.push_back({positions[corner], normal, barycentric[corner], uv});
    }
    ++destination.triangleCount;
    destination.hasNormals = true;
  }

  const std::size_t vertexCount = destination.vertices.size() - firstVertex;
  if (vertexCount == 0) return true;

  MeshDrawRange range;
  range.firstVertex = firstVertex;
  range.vertexCount = vertexCount;
  range.visible = true;
  range.sourceObject = nodeId;
  if (source.mMaterialIndex < payload.materials.size()) {
    const AssimpMaterialInfo& material = payload.materials[source.mMaterialIndex];
    if (material.hasDiffuseColor) {
      range.hasBaseColor = true;
      range.baseColor = material.diffuseColor;
    }
  }
  destination.drawRanges.push_back(std::move(range));
  payload.hasTangents = payload.hasTangents || source.HasTangentsAndBitangents();
  return true;
}

bool visitNode(
    const aiScene& scene,
    const aiNode& node,
    const Matrix4& parentWorld,
    const std::string& parentId,
    unsigned int childIndex,
    std::size_t depth,
    MeshData& mesh,
    AssimpDccPayload& payload,
    bool& approximateNormals,
    std::size_t& skippedFaces,
    std::string& error) {
  if (depth > kMaxHierarchyDepth) {
    error = "Assimp node hierarchy exceeds the depth safety limit.";
    return false;
  }
  if (payload.nodes.size() >= kMaxNodes) {
    error = "Assimp scene exceeds the node safety limit.";
    return false;
  }

  const std::string id = nodeIdFor(parentId, childIndex);
  const Matrix4 local = fromAssimp(node.mTransformation);
  const Matrix4 world = multiply(parentWorld, local);
  if (!finiteMatrix(local) || !finiteMatrix(world)) {
    error = "Assimp scene contains a non-finite node transform.";
    return false;
  }

  AssimpNodeInfo nodeInfo;
  nodeInfo.id = id;
  nodeInfo.name = node.mName.C_Str();
  nodeInfo.parentId = parentId;
  nodeInfo.localTransform = transformArray(local);
  nodeInfo.meshIndices.reserve(node.mNumMeshes);
  for (unsigned int meshSlot = 0; meshSlot < node.mNumMeshes; ++meshSlot) {
    const unsigned int meshIndex = node.mMeshes[meshSlot];
    if (meshIndex >= scene.mNumMeshes || scene.mMeshes[meshIndex] == nullptr) {
      error = "Assimp node references an invalid mesh index.";
      return false;
    }
    nodeInfo.meshIndices.push_back(meshIndex);
  }
  payload.nodes.push_back(std::move(nodeInfo));

  MeshObjectPresentation object;
  object.objectId = id;
  object.label = node.mName.C_Str();
  object.type = "assimp.node";
  object.parentObjectId = parentId;
  object.visible = true;
  object.effectiveVisible = true;
  mesh.objectPresentation.push_back(std::move(object));

  for (unsigned int meshSlot = 0; meshSlot < node.mNumMeshes; ++meshSlot) {
    const aiMesh* sourceMesh = scene.mMeshes[node.mMeshes[meshSlot]];
    if (!appendAssimpMesh(
            scene,
            *sourceMesh,
            world,
            id,
            mesh,
            payload,
            approximateNormals,
            skippedFaces,
            error)) {
      return false;
    }
  }

  for (unsigned int index = 0; index < node.mNumChildren; ++index) {
    if (node.mChildren[index] == nullptr) {
      error = "Assimp scene contains a null child node.";
      return false;
    }
    if (!visitNode(
            scene,
            *node.mChildren[index],
            world,
            id,
            index,
            depth + 1,
            mesh,
            payload,
            approximateNormals,
            skippedFaces,
            error)) {
      return false;
    }
  }
  return true;
}

void readMaterials(const aiScene& scene, AssimpDccPayload& payload) {
  payload.materials.reserve(scene.mNumMaterials);
  for (unsigned int index = 0; index < scene.mNumMaterials; ++index) {
    AssimpMaterialInfo info;
    const aiMaterial* material = scene.mMaterials[index];
    if (material != nullptr) {
      aiString name;
      if (material->Get(AI_MATKEY_NAME, name) == AI_SUCCESS) {
        info.name = name.C_Str();
      }
      aiColor3D diffuse;
      if (material->Get(AI_MATKEY_COLOR_DIFFUSE, diffuse) == AI_SUCCESS) {
        info.hasDiffuseColor = true;
        info.diffuseColor = {
            std::clamp(diffuse.r, 0.0f, 1.0f),
            std::clamp(diffuse.g, 0.0f, 1.0f),
            std::clamp(diffuse.b, 0.0f, 1.0f),
        };
      }
      info.diffuseTextureCount = material->GetTextureCount(aiTextureType_DIFFUSE);
      payload.hasTextures = payload.hasTextures || info.diffuseTextureCount > 0;
    }
    payload.materials.push_back(std::move(info));
  }
}

}  // namespace
#endif

AssimpDccImportResult importDccWithAssimp(
    const std::string& path,
    const std::string& sourceFormat) {
  AssimpDccImportResult result;
  if (sourceFormat != "fbx" && sourceFormat != "dae" &&
      sourceFormat != "ply" && sourceFormat != "off" &&
      sourceFormat != "gltf" && sourceFormat != "glb" &&
      sourceFormat != "3ds" && sourceFormat != "dxf") {
    result.error = "BrepSight has not validated this format through the Assimp provider.";
    return result;
  }

#if !defined(BREPSIGHT_WITH_ASSIMP)
  (void)path;
  result.error = "Assimp DCC provider is not enabled in this build.";
  return result;
#else
  Assimp::Importer importer;
  constexpr unsigned int flags =
      aiProcess_Triangulate |
      aiProcess_JoinIdenticalVertices |
      aiProcess_ValidateDataStructure;
  const aiScene* scene = importer.ReadFile(path, flags);
  if (scene == nullptr || scene->mRootNode == nullptr) {
    const char* message = importer.GetErrorString();
    result.error = message != nullptr && message[0] != '\0'
        ? std::string("Assimp import failed: ") + message
        : "Assimp import failed without diagnostics.";
    return result;
  }
  if (scene->mNumMaterials > kMaxMaterials) {
    result.error = "Assimp scene exceeds the material safety limit.";
    return result;
  }

  auto payload = std::make_shared<AssimpDccPayload>();
  payload->sourceFormat = sourceFormat;
  payload->cameraCount = scene->mNumCameras;
  payload->animationCount = scene->mNumAnimations;
  readMaterials(*scene, *payload);

  auto mesh = std::make_shared<MeshData>();
  mesh->sourceFormat = sourceFormat;
  bool approximateNormals = false;
  std::size_t skippedFaces = 0;
  const Matrix4 identity;
  if (!visitNode(
          *scene,
          *scene->mRootNode,
          identity,
          "",
          0,
          0,
          *mesh,
          *payload,
          approximateNormals,
          skippedFaces,
          result.error)) {
    return result;
  }

  if (mesh->vertices.empty() || mesh->triangleCount == 0) {
    result.error = "Assimp scene contains no renderable triangle geometry.";
    return result;
  }

  std::string presentationError;
  if (!refreshMeshPresentation(*mesh, presentationError)) {
    result.error = "Assimp scene presentation graph is invalid: " + presentationError;
    return result;
  }

  if (payload->hasTextures) {
    payload->warnings.emplace_back(
        "Diffuse texture references are detected but the current GLES material path renders base color only.");
  }
  if (payload->hasTangents) {
    payload->warnings.emplace_back(
        "Tangents and bitangents are detected but are not stored in the current MeshVertex layout.");
  }
  if (payload->animationCount > 0) {
    payload->warnings.emplace_back(
        "Animation tracks are counted as metadata but are not played by the current viewer.");
  }
  if (payload->cameraCount > 0) {
    payload->warnings.emplace_back(
        "Imported cameras are counted as metadata but do not replace the viewer camera.");
  }
  if (approximateNormals) {
    payload->warnings.emplace_back(
        "At least one singular node transform required approximate normal transformation.");
  }
  if (skippedFaces > 0) {
    payload->warnings.emplace_back(
        "Non-triangle primitives remaining after Assimp triangulation were skipped.");
  }

  result.rootObjectCount = payload->nodes.empty() ? 0 : 1;
  result.hierarchyNodeCount = payload->nodes.size();
  result.displayMesh = std::move(mesh);
  result.payload = std::move(payload);
  return result;
#endif
}

}  // namespace brepsight
