#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "assimp_dcc_importer.h"

namespace fs = std::filesystem;

namespace {

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

struct Fixture {
  const char* format;
  const char* filename;
  bool expectUv;
};

void verifyFixture(const fs::path& root, const Fixture& fixture) {
  const fs::path path = root / fixture.filename;
  require(fs::is_regular_file(path), "fixture missing: " + path.string());
  require(fs::file_size(path) > 0, "fixture is empty: " + path.string());

  const auto imported =
      brepsight::importDccWithAssimp(path.string(), fixture.format);
  require(
      imported.ok(),
      std::string(fixture.format) + " provider failed: " + imported.error);
  require(imported.displayMesh != nullptr, "display mesh missing");
  require(imported.payload != nullptr, "provider payload missing");
  require(
      imported.displayMesh->sourceFormat == fixture.format,
      std::string(fixture.format) + " display-mesh format identity mismatch");
  require(
      imported.payload->sourceFormat == fixture.format,
      std::string(fixture.format) + " payload format identity mismatch");
  require(
      imported.displayMesh->triangleCount > 0,
      std::string(fixture.format) + " produced no renderable triangles");
  require(
      imported.displayMesh->bounds.valid,
      std::string(fixture.format) + " produced invalid bounds");
  require(
      imported.rootObjectCount >= 1,
      std::string(fixture.format) + " exposed no scene root");
  require(
      imported.hierarchyNodeCount >= 1,
      std::string(fixture.format) + " exposed no hierarchy nodes");

  if (fixture.expectUv) {
    require(
        imported.displayMesh->hasUv,
        std::string(fixture.format) + " textured fixture lost UV coordinates");
  }

  std::cout << fixture.format << ": triangles="
            << imported.displayMesh->triangleCount
            << ", hierarchy=" << imported.hierarchyNodeCount
            << ", materials=" << imported.payload->materials.size()
            << ", uv=" << (imported.displayMesh->hasUv ? "yes" : "no")
            << '\n';
}

}  // namespace

int main(int argc, char** argv) {
  try {
    require(argc == 2, "usage: brepsight_assimp_baseline_fixture_smoke <fixture-root>");
    const fs::path root = argv[1];
    require(fs::is_directory(root), "fixture root is not a directory");

    const std::vector<Fixture> fixtures = {
        {"fbx", "box.fbx", false},
        {"gltf", "BoxTextured.gltf", true},
        {"glb", "BoxTextured.glb", true},
        {"3ds", "RotatingCube.3DS", false},
        {"dxf", "PinkEggFromLW.dxf", false},
    };

    for (const auto& fixture : fixtures) verifyFixture(root, fixture);

    std::cout
        << "Assimp 0.1 pinned baseline fixture smoke passed for FBX, glTF, GLB, 3DS and DXF.\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "Assimp 0.1 baseline fixture smoke failure: "
              << error.what() << '\n';
    return 1;
  }
}
