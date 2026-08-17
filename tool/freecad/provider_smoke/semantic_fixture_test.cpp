#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepTools.hxx>
#include <TopoDS_Shape.hxx>

#include "brep_occt_importer.h"
#include "freecad_fcstd_importer.h"
#include "freecad_presentation_adapter.h"
#include "mesh_presentation.h"

namespace fs = std::filesystem;

namespace {

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

void requireNear(double actual, double expected, double tolerance, const std::string& label) {
  if (!std::isfinite(actual) || std::fabs(actual - expected) > tolerance) {
    throw std::runtime_error(
        label + " expected " + std::to_string(expected) +
        ", got " + std::to_string(actual));
  }
}

void writeBrep(const TopoDS_Shape& shape, const fs::path& path) {
  require(!shape.IsNull(), "clean-room box shape is null");
  require(BRepTools::Write(shape, path.string().c_str()), "BRepTools::Write failed");
  require(fs::is_regular_file(path) && fs::file_size(path) > 0, "BREP fixture was not written");
}

void verifyDirectBrep(const fs::path& path) {
  const brepsight::BrepOcctImportResult imported = brepsight::importBrepWithOcct(path.string());
  require(imported.ok(), "direct BREP importer failed: " + imported.error);
  require(imported.displayMesh->triangleCount >= 12, "box BREP should tessellate to at least 12 triangles");
  require(imported.displayMesh->hasNormals, "direct BREP display mesh should contain normals");
  require(imported.displayMesh->bounds.valid, "direct BREP display bounds are invalid");
  require(imported.displayMesh->drawRanges.empty(), "direct BREP should use the default single-draw fallback");
  require(imported.displayMesh->objectPresentation.empty(), "direct BREP should not invent object presentation");
  requireNear(imported.displayMesh->bounds.min.x, 0.0, 1.0e-4, "direct min.x");
  requireNear(imported.displayMesh->bounds.min.y, 0.0, 1.0e-4, "direct min.y");
  requireNear(imported.displayMesh->bounds.min.z, 0.0, 1.0e-4, "direct min.z");
  requireNear(imported.displayMesh->bounds.max.x, 10.0, 1.0e-4, "direct max.x");
  requireNear(imported.displayMesh->bounds.max.y, 20.0, 1.0e-4, "direct max.y");
  requireNear(imported.displayMesh->bounds.max.z, 30.0, 1.0e-4, "direct max.z");
}

const brepsight::FcStdObjectPayload& findObject(
    const brepsight::FcStdPayload& payload,
    const char* name) {
  for (const auto& object : payload.objects) {
    if (object.name == name) return object;
  }
  throw std::runtime_error("missing FCStd object payload: " + std::string(name));
}

const brepsight::MeshObjectPresentation& findPresentation(
    const brepsight::MeshData& mesh,
    const char* id) {
  for (const auto& object : mesh.objectPresentation) {
    if (object.objectId == id) return object;
  }
  throw std::runtime_error("missing object presentation: " + std::string(id));
}

const brepsight::MeshDrawRange& findRange(
    const brepsight::MeshData& mesh,
    const char* id) {
  for (const auto& range : mesh.drawRanges) {
    if (range.sourceObject == id) return range;
  }
  throw std::runtime_error("missing draw range: " + std::string(id));
}

void verifyPreparedFcStd(const fs::path& first, const fs::path& second, const fs::path& manifest) {
  const std::string logicalSource = "/virtual/clean-room.FCStd";
  std::ofstream out(manifest, std::ios::binary | std::ios::trunc);
  require(static_cast<bool>(out), "could not create prepared FCStd manifest");
  out << "BREPSIGHT_FCSTD_V2\n";
  out << "source\t" << logicalSource << "\n";
  out << "objects\t3\n";
  out << "object\tAssembly\tApp%3A%3APart\tMain%20Assembly\t10\t0\t0\t0\t0\t0\t1\n";
  out << "presentation\tAssembly\t1\t-\n";
  out << "object\tPrimary_Box\tPart%3A%3AFeature\tPrimary\t0\t0\t0\t0\t0\t0\t1\n";
  out << "presentation\tPrimary_Box\t1\t287454207\n";  // 0x112233FF
  out << "object\tOffset_Box\tPart%3A%3AFeature\tOffset\t10\t0\t0\t0\t0\t0\t1\n";
  out << "presentation\tOffset_Box\t0\t-\n";
  out << "group\tAssembly\tPrimary_Box\n";
  out << "group\tAssembly\tOffset_Box\n";
  out << "shape\tPrimary_Box\t" << first.string() << "\n";
  out << "shape\tOffset_Box\t" << second.string() << "\n";
  out.close();

  brepsight::FcStdImportResult imported = brepsight::importPreparedFcStd(manifest.string());
  require(imported.ok(), "prepared FCStd importer failed: " + imported.error);
  require(imported.sourcePathOverride == logicalSource, "FCStd source-path override was not preserved");
  require(imported.rootObjectCount == 1, "FCStd hierarchy should expose one root App::Part");
  require(imported.hierarchyNodeCount == 3, "FCStd should preserve three document objects");
  require(imported.payload != nullptr, "FCStd exact payload is missing");
  require(imported.payload->objects.size() == 3, "FCStd object payload count mismatch");
  require(imported.payload->shapes.size() == 2, "FCStd exact shape payload count mismatch");
  require(imported.displayMesh->triangleCount >= 24, "two box BREPs should produce at least 24 triangles");
  require(imported.displayMesh->bounds.valid, "FCStd visible display bounds are invalid");
  require(imported.displayMesh->drawRanges.size() == 2, "FCStd should emit one draw range per saved shape");

  // Offset_Box exists at x=20..25 but is hidden, so default visible bounds contain only Primary_Box at x=10..20.
  requireNear(imported.displayMesh->bounds.min.x, 10.0, 1.0e-4, "FCStd visible min.x");
  requireNear(imported.displayMesh->bounds.max.x, 20.0, 1.0e-4, "FCStd visible max.x");

  const auto& primary = findObject(*imported.payload, "Primary_Box");
  require(primary.parentName == "Assembly", "Primary_Box parent was not preserved");
  requireNear(primary.worldTransform.tx, 10.0, 1.0e-9, "Primary_Box world tx");
  require(primary.hasVisibility && primary.visible, "Primary_Box visibility metadata was not preserved");
  require(primary.hasShapeColor && primary.shapeColor == 287454207u, "Primary_Box ShapeColor metadata mismatch");

  const auto& offset = findObject(*imported.payload, "Offset_Box");
  require(offset.parentName == "Assembly", "Offset_Box parent was not preserved");
  requireNear(offset.worldTransform.tx, 20.0, 1.0e-9, "Offset_Box world tx");
  require(offset.hasVisibility && !offset.visible, "Offset_Box hidden state was not preserved");

  std::string presentationError;
  require(
      brepsight::attachFcStdObjectPresentation(imported, presentationError),
      "FCStd presentation adapter failed: " + presentationError);
  require(imported.displayMesh->objectPresentation.size() == 3, "generic presentation object count mismatch");

  const auto& assemblyInitial = findPresentation(*imported.displayMesh, "Assembly");
  const auto& primaryInitial = findPresentation(*imported.displayMesh, "Primary_Box");
  const auto& offsetInitial = findPresentation(*imported.displayMesh, "Offset_Box");
  require(assemblyInitial.visible && assemblyInitial.effectiveVisible, "Assembly should start visible");
  require(primaryInitial.visible && primaryInitial.effectiveVisible, "Primary_Box should start visible");
  require(!offsetInitial.visible && !offsetInitial.effectiveVisible, "Offset_Box local hidden state should be preserved");
  require(primaryInitial.hasGeometry && offsetInitial.hasGeometry, "shape-backed objects should be marked as geometry-bearing");
  require(!assemblyInitial.hasGeometry, "group-only Assembly should not be marked as geometry-bearing");
  require(primaryInitial.hasBaseColor, "Primary_Box generic presentation should keep ShapeColor");
  requireNear(primaryInitial.baseColor.x, 17.0 / 255.0, 1.0e-6, "Primary presentation red");
  requireNear(primaryInitial.baseColor.y, 34.0 / 255.0, 1.0e-6, "Primary presentation green");
  requireNear(primaryInitial.baseColor.z, 51.0 / 255.0, 1.0e-6, "Primary presentation blue");

  const auto& primaryRangeInitial = findRange(*imported.displayMesh, "Primary_Box");
  const auto& offsetRangeInitial = findRange(*imported.displayMesh, "Offset_Box");
  require(primaryRangeInitial.visible, "Primary draw range should be visible");
  require(!offsetRangeInitial.visible, "Offset draw range should be hidden");
  require(primaryRangeInitial.hasBaseColor, "Primary draw range should preserve ShapeColor");

  // Hiding a parent must hide descendants effectively without changing their local visibility state.
  require(
      brepsight::setMeshObjectVisibility(*imported.displayMesh, "Assembly", false, presentationError),
      "hiding Assembly failed: " + presentationError);
  require(!findPresentation(*imported.displayMesh, "Assembly").visible, "Assembly local visibility was not updated");
  require(!findPresentation(*imported.displayMesh, "Primary_Box").effectiveVisible, "parent-hidden Primary_Box remained effective-visible");
  require(findPresentation(*imported.displayMesh, "Primary_Box").visible, "parent hide mutated Primary_Box local visibility");
  require(!findPresentation(*imported.displayMesh, "Offset_Box").visible, "parent hide mutated Offset_Box local visibility");
  require(!findRange(*imported.displayMesh, "Primary_Box").visible, "parent-hidden Primary range remained visible");
  require(!findRange(*imported.displayMesh, "Offset_Box").visible, "parent-hidden Offset range remained visible");
  require(!imported.displayMesh->bounds.valid, "all-hidden document should expose invalid/empty visible bounds");

  // Re-showing the parent restores inherited visibility only; Offset_Box stays locally hidden.
  require(
      brepsight::setMeshObjectVisibility(*imported.displayMesh, "Assembly", true, presentationError),
      "showing Assembly failed: " + presentationError);
  require(findPresentation(*imported.displayMesh, "Primary_Box").effectiveVisible, "Primary_Box did not recover after parent show");
  require(!findPresentation(*imported.displayMesh, "Offset_Box").effectiveVisible, "Offset_Box local hidden state was lost after parent show");
  require(imported.displayMesh->bounds.valid, "visible bounds were not restored after parent show");
  requireNear(imported.displayMesh->bounds.max.x, 20.0, 1.0e-4, "restored parent visible max.x");

  // Explicitly showing Offset_Box should not reparse geometry; it only refreshes presentation and bounds.
  const std::size_t vertexCountBeforeToggle = imported.displayMesh->vertices.size();
  const auto exactShapeCountBeforeToggle = imported.payload->shapes.size();
  require(
      brepsight::setMeshObjectVisibility(*imported.displayMesh, "Offset_Box", true, presentationError),
      "showing Offset_Box failed: " + presentationError);
  require(imported.displayMesh->vertices.size() == vertexCountBeforeToggle, "visibility toggle rebuilt the vertex buffer");
  require(imported.payload->shapes.size() == exactShapeCountBeforeToggle, "visibility toggle changed exact payload shape count");
  require(findPresentation(*imported.displayMesh, "Offset_Box").visible, "Offset_Box local visibility did not update");
  require(findPresentation(*imported.displayMesh, "Offset_Box").effectiveVisible, "Offset_Box effective visibility did not update");
  require(findRange(*imported.displayMesh, "Offset_Box").visible, "Offset draw range did not become visible");
  requireNear(imported.displayMesh->bounds.max.x, 25.0, 1.0e-4, "toggle-visible max.x");

  const std::string json = brepsight::meshObjectPresentationJson(*imported.displayMesh);
  require(json.find("\"id\":\"Assembly\"") != std::string::npos, "presentation JSON omitted Assembly");
  require(json.find("\"id\":\"Offset_Box\"") != std::string::npos, "presentation JSON omitted Offset_Box");
  require(json.find("\"effectiveVisible\":true") != std::string::npos, "presentation JSON omitted effective visibility");
}

}  // namespace

int main() {
  try {
    const fs::path root = fs::current_path() / ".build" / "fcstd-host-semantic";
    fs::remove_all(root);
    fs::create_directories(root);

    const fs::path primaryPath = root / "primary.brp";
    const fs::path offsetPath = root / "offset.brep";
    const fs::path manifestPath = root / "document.fcstdmanifest";

    const TopoDS_Shape primary = BRepPrimAPI_MakeBox(10.0, 20.0, 30.0).Shape();
    const TopoDS_Shape offset = BRepPrimAPI_MakeBox(5.0, 5.0, 5.0).Shape();
    writeBrep(primary, primaryPath);
    writeBrep(offset, offsetPath);

    verifyDirectBrep(primaryPath);
    verifyPreparedFcStd(primaryPath, offsetPath, manifestPath);

    std::cout
        << "FCStd semantic smoke passed: real BREP read, generic object presentation, inherited/local visibility toggles, "
        << "stable exact/vertex payload, ShapeColor, nested placement, source override, and live visible bounds verified.\n";
    fs::remove_all(root);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FCStd semantic smoke failure: " << error.what() << '\n';
    return 1;
  }
}
