#include "brep_occt_importer.h"

#if defined(BREPSIGHT_WITH_OCCT)

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <exception>
#include <filesystem>
#include <memory>
#include <string>

#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <Poly_Triangulation.hxx>
#include <Standard_Failure.hxx>
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

constexpr std::uintmax_t kMaxBrepFileBytes = 512ULL * 1024ULL * 1024ULL;
constexpr std::size_t kMaxBrepFaces = 250000;
constexpr std::size_t kMaxExpandedTriangles = 5000000;

bool toFiniteVec3(const gp_Pnt& point, Vec3& output) {
  const double x = point.X();
  const double y = point.Y();
  const double z = point.Z();
  if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z)) return false;
  const float fx = static_cast<float>(x);
  const float fy = static_cast<float>(y);
  const float fz = static_cast<float>(z);
  if (!std::isfinite(fx) || !std::isfinite(fy) || !std::isfinite(fz)) return false;
  output = {fx, fy, fz};
  return true;
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
  if (std::isfinite(length) && length > 1.0e-20f) {
    nx /= length;
    ny /= length;
    nz /= length;
  } else {
    nx = 0.0f;
    ny = 0.0f;
    nz = 1.0f;
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

bool validateInputSize(const std::string& path, std::string& error) {
  std::error_code filesystemError;
  const std::uintmax_t size = std::filesystem::file_size(path, filesystemError);
  if (filesystemError) {
    error = "BREP/BRP source size could not be inspected safely.";
    return false;
  }
  if (size == 0 || size > kMaxBrepFileBytes) {
    error = "BREP/BRP source size is outside the supported safety limit.";
    return false;
  }
  return true;
}

bool validateTopologyComplexity(const TopoDS_Shape& shape, std::string& error) {
  std::size_t faceCount = 0;
  for (TopExp_Explorer explorer(shape, TopAbs_FACE); explorer.More(); explorer.Next()) {
    ++faceCount;
    if (faceCount > kMaxBrepFaces) {
      error = "BREP/BRP face count exceeds the safe tessellation limit.";
      return false;
    }
  }
  if (faceCount == 0) {
    error = "BREP/BRP contains no faces that can be displayed as a surface model.";
    return false;
  }
  return true;
}

bool tessellateShape(const TopoDS_Shape& shape, MeshData& output, std::string& error) {
  if (shape.IsNull()) {
    error = "BREP/BRP shape is null.";
    return false;
  }
  if (!validateTopologyComplexity(shape, error)) return false;

  BRepMesh_IncrementalMesh mesher(shape, 0.001, true, 0.5, true);
  if (!mesher.IsDone()) {
    error = "OCCT could not tessellate the saved BREP/BRP shape.";
    return false;
  }

  for (TopExp_Explorer explorer(shape, TopAbs_FACE); explorer.More(); explorer.Next()) {
    const TopoDS_Face face = TopoDS::Face(explorer.Current());
    TopLoc_Location location;
    const occ::handle<Poly_Triangulation>& triangulation = BRep_Tool::Triangulation(face, location);
    if (triangulation.IsNull() || triangulation->NbTriangles() <= 0) continue;

    const std::size_t faceTriangles = static_cast<std::size_t>(triangulation->NbTriangles());
    if (faceTriangles > kMaxExpandedTriangles - output.triangleCount) {
      error = "BREP/BRP display tessellation exceeds the triangle safety limit.";
      return false;
    }

    const gp_Trsf transform = location.Transformation();
    const bool reverse = face.Orientation() == TopAbs_REVERSED;
    for (int triangleIndex = 1; triangleIndex <= triangulation->NbTriangles(); ++triangleIndex) {
      int first = 0;
      int second = 0;
      int third = 0;
      triangulation->Triangle(triangleIndex).Get(first, second, third);
      if (first < 1 || second < 1 || third < 1 ||
          first > triangulation->NbNodes() ||
          second > triangulation->NbNodes() ||
          third > triangulation->NbNodes()) {
        error = "BREP/BRP triangulation contains an invalid node index.";
        return false;
      }

      Vec3 a{};
      Vec3 b{};
      Vec3 c{};
      if (!toFiniteVec3(triangulation->Node(first).Transformed(transform), a) ||
          !toFiniteVec3(triangulation->Node(second).Transformed(transform), b) ||
          !toFiniteVec3(triangulation->Node(third).Transformed(transform), c)) {
        error = "BREP/BRP tessellation produced a non-finite coordinate.";
        return false;
      }
      appendTriangle(output, a, b, c, reverse);
    }
  }

  if (output.vertices.empty()) {
    error = "Saved BREP geometry loaded, but display tessellation produced no triangles.";
    return false;
  }
  return true;
}

}  // namespace

BrepOcctImportResult importBrepWithOcct(const std::string& path) {
  BrepOcctImportResult result;
  try {
    if (!validateInputSize(path, result.error)) return result;

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
    if (!tessellateShape(shape, *mesh, result.error)) return result;

    result.displayMesh = std::move(mesh);
    result.exactPayload = std::make_shared<TopoDS_Shape>(shape);
    return result;
  } catch (const Standard_Failure& error) {
    const char* message = error.GetMessageString();
    result.error = message == nullptr || *message == '\0'
        ? "OCCT failed while reading BREP/BRP geometry."
        : std::string("OCCT BREP/BRP failure: ") + message;
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
