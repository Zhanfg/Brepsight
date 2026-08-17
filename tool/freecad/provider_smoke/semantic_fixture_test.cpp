#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepTools.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Pnt.hxx>

#include "brep_occt_importer.h"
#include "freecad_fcstd_importer.h"

namespace fs = std::filesystem;

namespace {

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

void requireNear(float actual, float expected, float tolerance, const std::string& label) {
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
  requireNear(imported.displayMesh->bounds.min.x, 0.0f, 1.0e-4f, "direct min.x");
  requireNear(imported.displayMesh->bounds.min.y, 0.0f, 1.0e-4f, "direct min.y");
  requireNear(imported.displayMesh->bounds.min.z, 0.0f, 1.0e-4f, "direct min.z");
  requireNear(imported.displayMesh->bounds.max.x, 10.0f, 1.0e-4f, "direct max.x");
  requireNear(imported.displayMesh->bounds.max.y, 20.0f, 1.0e-4f, "direct max.y");
  requireNear(imported.displayMesh->bounds.max.z, 30.0f, 1.0e-4f, "direct max.z");
}

void verifyPreparedFcStd(const fs::path& first, const fs::path& second, const fs::path& manifest) {
  const std::string logicalSource = "/virtual/clean-room.FCStd";
  std::ofstream out(manifest, std::ios::binary | std::ios::trunc);
  require(static_cast<bool>(out), "could not create prepared FCStd manifest");
  out << "BREPSIGHT_FCSTD_V1\n";
  out << "source\t" << logicalSource << "\n";
  out << "objects\t3\n";
  out << "shape\tPrimary_Box\t" << first.string() << "\n";
  out << "shape\tOffset_Box\t" << second.string() << "\n";
  out.close();

  const brepsight::FcStdImportResult imported = brepsight::importPreparedFcStd(manifest.string());
  require(imported.ok(), "prepared FCStd importer failed: " + imported.error);
  require(imported.sourcePathOverride == logicalSource, "FCStd source-path override was not preserved");
  require(imported.rootObjectCount == 2, "FCStd should expose two readable saved shapes");
  require(imported.hierarchyNodeCount == 3, "FCStd should preserve the declared document object count");
  require(imported.payload != nullptr, "FCStd exact payload is missing");
  require(imported.displayMesh->triangleCount >= 24, "two box BREPs should produce at least 24 triangles");
  require(imported.displayMesh->bounds.valid, "FCStd merged display bounds are invalid");

  requireNear(imported.displayMesh->bounds.min.x, 0.0f, 1.0e-4f, "FCStd min.x");
  requireNear(imported.displayMesh->bounds.min.y, 0.0f, 1.0e-4f, "FCStd min.y");
  requireNear(imported.displayMesh->bounds.min.z, 0.0f, 1.0e-4f, "FCStd min.z");
  requireNear(imported.displayMesh->bounds.max.x, 25.0f, 1.0e-4f, "FCStd max.x");
  requireNear(imported.displayMesh->bounds.max.y, 20.0f, 1.0e-4f, "FCStd max.y");
  requireNear(imported.displayMesh->bounds.max.z, 30.0f, 1.0e-4f, "FCStd max.z");
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
    const TopoDS_Shape offset = BRepPrimAPI_MakeBox(gp_Pnt(20.0, 0.0, 0.0), 5.0, 5.0, 5.0).Shape();
    writeBrep(primary, primaryPath);
    writeBrep(offset, offsetPath);

    verifyDirectBrep(primaryPath);
    verifyPreparedFcStd(primaryPath, offsetPath, manifestPath);

    std::cout
        << "FCStd semantic smoke passed: real BREP read, exact payload, merged bounds, "
        << "source override, and hierarchy counts verified.\n";
    fs::remove_all(root);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FCStd semantic smoke failure: " << error.what() << '\n';
    return 1;
  }
}
