#include <cmath>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

#include <BRepPrimAPI_MakeBox.hxx>
#include <IGESControl_Writer.hxx>
#include <TopoDS_Shape.hxx>

#include "iges_occt_importer.h"

namespace {

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

void writeFixture(const std::filesystem::path& path) {
  const TopoDS_Shape box = BRepPrimAPI_MakeBox(10.0, 20.0, 30.0).Shape();
  require(!box.IsNull(), "failed to construct OCCT box fixture");

  IGESControl_Writer writer("MM", 0);
  require(writer.AddShape(box), "IGES writer rejected the box shape");
  require(writer.Write(path.string().c_str()), "IGES writer failed to write fixture");
}

}  // namespace

int main(int argc, char** argv) {
  try {
    const std::filesystem::path fixture =
        argc > 1 ? std::filesystem::path(argv[1]) : std::filesystem::path("brepsight-contract.igs");
    writeFixture(fixture);
    require(std::filesystem::file_size(fixture) > 0, "generated IGES fixture is empty");

    const brepsight::IgesOcctImportResult result =
        brepsight::importIgesWithOcct(fixture.string());
    require(result.error.empty(), "IGES importer returned: " + result.error);
    require(result.displayMesh != nullptr, "IGES importer produced no display mesh");
    require(result.exactPayload != nullptr, "IGES exact XCAF/B-Rep payload was lost");
    require(result.displayMesh->sourceFormat == "iges", "source format identity changed");
    require(result.displayMesh->triangleCount > 0, "IGES display tessellation is empty");
    require(!result.displayMesh->vertices.empty(), "IGES display vertices are empty");
    require(result.displayMesh->bounds.valid, "IGES bounds are invalid");
    require(result.displayMesh->hasNormals, "IGES display normals were not generated");
    require(result.rootShapeCount >= 1, "IGES root shape count is empty");
    require(result.hierarchyNodeCount >= 1, "IGES XCAF hierarchy count is empty");

    const auto& bounds = result.displayMesh->bounds;
    const double dx = static_cast<double>(bounds.max.x - bounds.min.x);
    const double dy = static_cast<double>(bounds.max.y - bounds.min.y);
    const double dz = static_cast<double>(bounds.max.z - bounds.min.z);
    require(std::isfinite(dx) && std::isfinite(dy) && std::isfinite(dz), "IGES extents are non-finite");
    require(dx > 9.9 && dy > 19.9 && dz > 29.9, "IGES box dimensions were not preserved");

    std::cout << "OCCT IGES semantic contract passed: triangles="
              << result.displayMesh->triangleCount
              << " roots=" << result.rootShapeCount
              << " hierarchy=" << result.hierarchyNodeCount << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "OCCT IGES semantic contract failed: " << error.what() << '\n';
    return 1;
  }
}
