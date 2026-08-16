#include "step_occt_importer.h"

#if defined(BREPSIGHT_WITH_OCCT)

#include <algorithm>
#include <array>
#include <cmath>
#include <exception>
#include <memory>
#include <vector>

#include <BRep_Tool.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <NCollection_Sequence.hxx>
#include <Poly_Triangle.hxx>
#include <Poly_Triangulation.hxx>
#include <STEPCAFControl_Reader.hxx>
#include <TDocStd_Document.hxx>
#include <TDF_Label.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shape.hxx>
#include <XCAFApp_Application.hxx>
#include <XCAFDoc_DocumentTool.hxx>
#include <XCAFDoc_ShapeTool.hxx>
#include <gp_Pnt.hxx>

namespace brepsight {
namespace {

struct OcctStepPayload {
  occ::handle<TDocStd_Document> document;
  std::vector<TopoDS_Shape> rootShapes;

  ~OcctStepPayload() {
    if (!document.IsNull()) {
      const occ::handle<XCAFApp_Application> application =
          XCAFApp_Application::GetApplication();
      if (!application.IsNull()) application->Close(document);
      document.Nullify();
    }
  }
};

Vec3 toVec3(const gp_Pnt& p) {
  return {
      static_cast<float>(p.X()),
      static_cast<float>(p.Y()),
      static_cast<float>(p.Z()),
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

void appendTriangle(MeshData& out, Vec3 a, Vec3 b, Vec3 c, bool reverse) {
  if (reverse) std::swap(b, c);
  const Vec3 normal = triangleNormal(a, b, c);
  const std::array<Vec3, 3> bary = {
      Vec3{1.0f, 0.0f, 0.0f},
      Vec3{0.0f, 1.0f, 0.0f},
      Vec3{0.0f, 0.0f, 1.0f},
  };
  const std::array<Vec3, 3> points = {a, b, c};
  for (std::size_t i = 0; i < points.size(); ++i) {
    out.vertices.push_back(MeshVertex{points[i], normal, bary[i], Vec2{0.0f, 0.0f}});
    out.bounds.include(points[i]);
  }
  ++out.triangleCount;
}

void appendShapeMesh(const TopoDS_Shape& shape, MeshData& out) {
  if (shape.IsNull()) return;

  BRepMesh_IncrementalMesh mesher(shape, 0.001, true, 0.5, true);
  if (!mesher.IsDone()) return;

  for (TopExp_Explorer explorer(shape, TopAbs_FACE); explorer.More(); explorer.Next()) {
    const TopoDS_Face face = TopoDS::Face(explorer.Current());
    TopLoc_Location location;
    const occ::handle<Poly_Triangulation>& triangulation =
        BRep_Tool::Triangulation(face, location);
    if (triangulation.IsNull() || triangulation->NbTriangles() <= 0) continue;

    const gp_Trsf transform = location.Transformation();
    const bool reverse = face.Orientation() == TopAbs_REVERSED;
    for (int triangleIndex = 1;
         triangleIndex <= triangulation->NbTriangles();
         ++triangleIndex) {
      int n1 = 0;
      int n2 = 0;
      int n3 = 0;
      triangulation->Triangle(triangleIndex).Get(n1, n2, n3);
      const gp_Pnt p1 = triangulation->Node(n1).Transformed(transform);
      const gp_Pnt p2 = triangulation->Node(n2).Transformed(transform);
      const gp_Pnt p3 = triangulation->Node(n3).Transformed(transform);
      appendTriangle(out, toVec3(p1), toVec3(p2), toVec3(p3), reverse);
    }
  }
}

std::size_t countAssemblyNodes(
    const occ::handle<XCAFDoc_ShapeTool>& shapeTool,
    const TDF_Label& label) {
  if (shapeTool.IsNull() || label.IsNull()) return 0;
  std::size_t count = 1;
  NCollection_Sequence<TDF_Label> children;
  if (XCAFDoc_ShapeTool::GetComponents(label, children, false)) {
    for (int index = 1; index <= children.Length(); ++index) {
      count += countAssemblyNodes(shapeTool, children.Value(index));
    }
  }
  return count;
}

}  // namespace

StepOcctImportResult importStepWithOcct(const std::string& path) {
  StepOcctImportResult result;
  try {
    const occ::handle<XCAFApp_Application> application =
        XCAFApp_Application::GetApplication();
    occ::handle<TDocStd_Document> document;
    application->NewDocument("BinXCAF", document);
    if (document.IsNull()) {
      result.error = "OCCT failed to create an XCAF document.";
      return result;
    }

    STEPCAFControl_Reader reader;
    reader.SetColorMode(true);
    reader.SetLayerMode(true);
    reader.SetNameMode(true);
    reader.SetPropsMode(true);
    if (!reader.Perform(path.c_str(), document)) {
      application->Close(document);
      result.error = "STEPCAFControl_Reader failed to transfer the STEP document.";
      return result;
    }

    const occ::handle<XCAFDoc_ShapeTool> shapeTool =
        XCAFDoc_DocumentTool::ShapeTool(document->Main());
    if (shapeTool.IsNull()) {
      application->Close(document);
      result.error = "STEP document has no XCAF shape tool.";
      return result;
    }

    NCollection_Sequence<TDF_Label> freeLabels;
    shapeTool->GetFreeShapes(freeLabels);
    if (freeLabels.IsEmpty()) {
      application->Close(document);
      result.error = "STEP document contains no free/root shapes.";
      return result;
    }

    auto payload = std::make_shared<OcctStepPayload>();
    payload->document = document;
    payload->rootShapes.reserve(static_cast<std::size_t>(freeLabels.Length()));

    auto mesh = std::make_shared<MeshData>();
    mesh->sourceFormat = "step";
    mesh->hasNormals = true;
    mesh->hasUv = false;

    for (int index = 1; index <= freeLabels.Length(); ++index) {
      const TDF_Label& label = freeLabels.Value(index);
      const TopoDS_Shape shape = XCAFDoc_ShapeTool::GetShape(label);
      if (shape.IsNull()) continue;
      payload->rootShapes.push_back(shape);
      appendShapeMesh(shape, *mesh);
      result.assemblyNodeCount += countAssemblyNodes(shapeTool, label);
    }

    if (payload->rootShapes.empty()) {
      payload.reset();
      result.error = "STEP XCAF roots did not contain usable shapes.";
      return result;
    }
    if (mesh->vertices.empty()) {
      payload.reset();
      result.error = "STEP loaded as exact B-Rep, but display tessellation produced no triangles.";
      return result;
    }

    result.rootShapeCount = payload->rootShapes.size();
    result.displayMesh = std::move(mesh);
    result.exactPayload = std::move(payload);
    return result;
  } catch (const std::exception& error) {
    result.error = error.what();
    return result;
  } catch (...) {
    result.error = "Unknown OCCT exception while reading STEP.";
    return result;
  }
}

}  // namespace brepsight

#else

namespace brepsight {
StepOcctImportResult importStepWithOcct(const std::string&) {
  StepOcctImportResult result;
  result.error = "BrepSight was built without the OCCT STEP provider.";
  return result;
}
}  // namespace brepsight

#endif
