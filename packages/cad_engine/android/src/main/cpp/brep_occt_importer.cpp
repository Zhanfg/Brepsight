#include "brep_occt_importer.h"

#if defined(BREPSIGHT_WITH_OCCT)

#include <algorithm>
#include <array>
#include <cmath>
#include <exception>
#include <memory>

#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <Poly_Triangulation.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Pnt.hxx>

namespace brepsight {
namespace {

Vec3 toVec3(const gp_Pnt& point) {
  return {
      static_cast<float>(point.X()),
      static_cast<float>(point.Y()),
      static_cast<float>(point.Z()),
  };
}

Vec3 triangleNormal(const Vec3& a, const Vec3& b, const Vec3& c) {
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
  if (length > 1.0e-20f) {
    nx /= length;
    ny /= length;
    nz /= length;
  }
  return {nx, ny, nz};
}

void appendTriangle(MeshData& output, Vec3 a, Vec3 b, Vec3 c, bool reverse) {
  if (reverse) std::swap(b, c);
  const Vec3 normal = triangleNormal(a, b, c);
  const std::array<Vec3, 3> barycentric = {
      Vec3{1.0f, 0.0f, 0.0f},
      Vec3{0.0f, 1.0f, 0.0f},
      Vec3{0.0f, 0.0f, 1.0f},
  };
  const std::array<Vec3, 3> points = {a, b, c};
  for (std::size_t index = 0; index < points.size(); ++index) {
    output.vertices.push_back(MeshVertex{points[index], normal, barycentric[index], Vec2{0.0f, 0.0f}});
    output.bounds.include(points[index]);
  }
  ++output.triangleCount;
}

bool tessellateShape(const TopoDS_Shape& shape, MeshData& output) {
  if (shape.IsNull()) return false;
  BRepMesh_IncrementalMesh mesher(shape, 0.001, true, 0.5, true);
  if (!mesher.IsDone()) return false;

  for (TopExp_Explorer explorer(shape, TopAbs_FACE); explorer.More(); explorer.Next()) {
    const TopoDS_Face face = TopoDS::Face(explorer.Current());
    TopLoc_Location location;
    const occ::handle<Poly_Triangulation>& triangulation = BRep_Tool::Triangulation(face, location);
    if (triangulation.IsNull() || triangulation->NbTriangles() <= 0) continue;

    const gp_Trsf transform = location.Transformation();
    const bool reverse = face.Orientation() == TopAbs_REVERSED;
    for (int triangleIndex = 1; triangleIndex <= triangulation->NbTriangles(); ++triangleIndex) {
      int first = 0;
      int second = 0;
      int third = 0;
      triangulation->Triangle(triangleIndex).Get(first, second, third);
      appendTriangle(
          output,
          toVec3(triangulation->Node(first).Transformed(transform)),
          toVec3(triangulation->Node(second).Transformed(transform)),
          toVec3(triangulation->Node(third).Transformed(transform)),
          reverse);
    }
  }
  return !output.vertices.empty();
}

}  // namespace

BrepOcctImportResult importBrepWithOcct(const std::string& path) {
  BrepOcctImportResult result;
  try {
    BRep_Builder builder;
    TopoDS_Shape shape;
    if (!BRepTools::Read(shape, path.c_str(), builder) || shape.IsNull()) {
      result.error = "OCCT could not read the saved BREP/BRP shape.";
      return result;
    }

    auto mesh = std::make_shared<MeshData>();
    mesh->sourceFormat = "brep";
    mesh->hasNormals = true;
    mesh->hasUv = false;
    if (!tessellateShape(shape, *mesh)) {
      result.error = "Saved BREP geometry loaded, but display tessellation produced no triangles.";
      return result;
    }

    result.displayMesh = std::move(mesh);
    result.exactPayload = std::make_shared<TopoDS_Shape>(shape);
    return result;
  } catch (const std::exception& error) {
    result.error = error.what();
    return result;
  } catch (...) {
    result.error = "Unknown OCCT exception while reading BREP/BRP.";
    return result;
  }
}

}  // namespace brepsight

#else

namespace brepsight {
BrepOcctImportResult importBrepWithOcct(const std::string&) {
  BrepOcctImportResult result;
  result.error = "BrepSight was built without the OCCT BREP provider.";
  return result;
}
}  // namespace brepsight

#endif
