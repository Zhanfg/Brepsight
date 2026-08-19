#include "rhino_3dm_importer.h"

#include <array>
#include <cmath>
#include <mutex>
#include <string>

#include "mesh_presentation.h"

#if defined(BREPSIGHT_WITH_OPENNURBS)
#include <opennurbs_public.h>
#endif

namespace brepsight {

#if defined(BREPSIGHT_WITH_OPENNURBS)
namespace {

constexpr std::size_t kMaxOutputVertices = 6000000;
std::once_flag gOpenNurbsInit;

Vec3 toVec3(const ON_3dPoint& point) {
  return {
      static_cast<float>(point.x),
      static_cast<float>(point.y),
      static_cast<float>(point.z),
  };
}

Vec3 normalOf(const Vec3& a, const Vec3& b, const Vec3& c) {
  const float ux = b.x - a.x;
  const float uy = b.y - a.y;
  const float uz = b.z - a.z;
  const float vx = c.x - a.x;
  const float vy = c.y - a.y;
  const float vz = c.z - a.z;
  float nx = uy * vz - uz * vy;
  float ny = uz * vx - ux * vz;
  float nz = ux * vy - uy * vx;
  const float length = std::sqrt(nx * nx + ny * ny + nz * nz);
  if (length <= 1.0e-20f || !std::isfinite(length)) return {0.0f, 0.0f, 1.0f};
  return {nx / length, ny / length, nz / length};
}

bool appendTriangle(
    const ON_Mesh& source,
    int aIndex,
    int bIndex,
    int cIndex,
    MeshData& out,
    std::string& error) {
  if (aIndex < 0 || bIndex < 0 || cIndex < 0 ||
      aIndex >= source.VertexCount() || bIndex >= source.VertexCount() ||
      cIndex >= source.VertexCount()) {
    error = "3DM render mesh contains an invalid face vertex index.";
    return false;
  }
  if (out.vertices.size() > kMaxOutputVertices - 3) {
    error = "3DM render mesh exceeds the mobile vertex safety limit.";
    return false;
  }

  const std::array<Vec3, 3> points = {
      toVec3(source.Vertex(aIndex)),
      toVec3(source.Vertex(bIndex)),
      toVec3(source.Vertex(cIndex)),
  };
  for (const Vec3& point : points) {
    if (!std::isfinite(point.x) || !std::isfinite(point.y) || !std::isfinite(point.z)) {
      error = "3DM render mesh contains a non-finite vertex.";
      return false;
    }
  }
  const Vec3 normal = normalOf(points[0], points[1], points[2]);
  static constexpr std::array<Vec3, 3> barycentric = {
      Vec3{1.0f, 0.0f, 0.0f},
      Vec3{0.0f, 1.0f, 0.0f},
      Vec3{0.0f, 0.0f, 1.0f},
  };
  for (std::size_t corner = 0; corner < 3; ++corner) {
    out.vertices.push_back({points[corner], normal, barycentric[corner], Vec2{0.0f, 0.0f}});
    out.bounds.include(points[corner]);
  }
  ++out.triangleCount;
  out.hasNormals = true;
  return true;
}

bool appendMesh(
    const ON_Mesh& source,
    const std::string& objectId,
    MeshData& out,
    std::string& error) {
  const std::size_t firstVertex = out.vertices.size();
  for (int faceIndex = 0; faceIndex < source.FaceCount(); ++faceIndex) {
    const ON_MeshFace& face = source.m_F[faceIndex];
    if (!appendTriangle(source, face.vi[0], face.vi[1], face.vi[2], out, error)) return false;
    if (face.IsQuad()) {
      if (!appendTriangle(source, face.vi[0], face.vi[2], face.vi[3], out, error)) return false;
    }
  }
  const std::size_t vertexCount = out.vertices.size() - firstVertex;
  if (vertexCount > 0) {
    MeshDrawRange range;
    range.firstVertex = firstVertex;
    range.vertexCount = vertexCount;
    range.visible = true;
    range.sourceObject = objectId;
    out.drawRanges.push_back(std::move(range));
  }
  return vertexCount > 0;
}

bool appendGeometryRenderMeshes(
    const ON_Geometry& geometry,
    const std::string& objectId,
    MeshData& out,
    std::string& error) {
  if (const ON_Mesh* mesh = ON_Mesh::Cast(&geometry)) {
    return appendMesh(*mesh, objectId, out, error);
  }
  if (const ON_Brep* brep = ON_Brep::Cast(&geometry)) {
    ON_SimpleArray<const ON_Mesh*> meshes;
    brep->GetMesh(ON::render_mesh, meshes);
    bool appended = false;
    for (int index = 0; index < meshes.Count(); ++index) {
      if (meshes[index] != nullptr) {
        appended = appendMesh(*meshes[index], objectId, out, error) || appended;
        if (!error.empty()) return false;
      }
    }
    return appended;
  }
  if (const ON_Extrusion* extrusion = ON_Extrusion::Cast(&geometry)) {
    const ON_Mesh* mesh = extrusion->m_mesh_cache.Mesh(ON::render_mesh);
    return mesh != nullptr && appendMesh(*mesh, objectId, out, error);
  }
  return false;
}

}  // namespace
#endif

Rhino3dmImportResult importRhino3dm(const std::string& path) {
  Rhino3dmImportResult result;
#if !defined(BREPSIGHT_WITH_OPENNURBS)
  (void)path;
  result.error = "BrepSight was built without the openNURBS 3DM provider.";
  return result;
#else
  std::call_once(gOpenNurbsInit, [] { ON::Begin(); });

  ON_TextLog diagnostics;
  ONX_Model model;
  if (!model.Read(path.c_str(), &diagnostics)) {
    result.error = "openNURBS failed to read the 3DM document.";
    return result;
  }

  auto mesh = std::make_shared<MeshData>();
  mesh->sourceFormat = "3dm";
  auto payload = std::make_shared<Rhino3dmPayload>();

  ONX_ModelComponentIterator iterator(model, ON_ModelComponent::Type::ModelGeometry);
  const ON_ModelComponent* component = nullptr;
  std::size_t objectIndex = 0;
  for (component = iterator.FirstComponent(); component != nullptr; component = iterator.NextComponent()) {
    const ON_ModelGeometryComponent* modelGeometry =
        ON_ModelGeometryComponent::Cast(component);
    if (modelGeometry == nullptr) continue;
    const ON_Geometry* geometry = modelGeometry->Geometry(nullptr);
    if (geometry == nullptr) continue;

    ++payload->geometryObjectCount;
    const std::string objectId = "rhino/" + std::to_string(objectIndex++);
    const std::size_t before = mesh->vertices.size();
    std::string error;
    const bool rendered = appendGeometryRenderMeshes(*geometry, objectId, *mesh, error);
    if (!error.empty()) {
      result.error = std::move(error);
      return result;
    }

    MeshObjectPresentation presentation;
    presentation.objectId = objectId;
    presentation.label = "Rhino object " + std::to_string(objectIndex);
    presentation.type = "rhino.model_geometry";
    presentation.visible = true;
    presentation.effectiveVisible = true;
    presentation.hasGeometry = rendered && mesh->vertices.size() > before;
    mesh->objectPresentation.push_back(std::move(presentation));
    if (rendered) ++payload->renderMeshObjectCount;
  }

  if (mesh->vertices.empty() || mesh->triangleCount == 0) {
    result.error =
        "3DM was parsed, but it contains no saved render mesh that BrepSight 0.1 can display.";
    return result;
  }

  std::string presentationError;
  if (!refreshMeshPresentation(*mesh, presentationError)) {
    result.error = "3DM presentation graph is invalid: " + presentationError;
    return result;
  }
  if (payload->renderMeshObjectCount < payload->geometryObjectCount) {
    payload->warnings.emplace_back(
        "Some Rhino geometry has no saved render mesh; those objects remain listed but are not triangulated by the 0.1 mobile provider.");
  }

  result.rootObjectCount = mesh->objectPresentation.size();
  result.hierarchyNodeCount = mesh->objectPresentation.size();
  result.displayMesh = std::move(mesh);
  result.payload = std::move(payload);
  return result;
#endif
}

}  // namespace brepsight
