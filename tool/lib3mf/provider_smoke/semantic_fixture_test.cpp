#include "three_mf_importer.h"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>

namespace {

bool near(float actual, float expected, float epsilon = 1.0e-3f) {
  return std::fabs(actual - expected) <= epsilon;
}

int fail(const std::string& message) {
  std::cerr << "3MF semantic fixture failure: " << message << '\n';
  return 1;
}

float signedVolume(const brepsight::MeshData& mesh) {
  float volume = 0.0f;
  for (std::size_t index = 0; index + 2 < mesh.vertices.size(); index += 3) {
    const auto& a = mesh.vertices[index].position;
    const auto& b = mesh.vertices[index + 1].position;
    const auto& c = mesh.vertices[index + 2].position;
    const float cx = b.y * c.z - b.z * c.y;
    const float cy = b.z * c.x - b.x * c.z;
    const float cz = b.x * c.y - b.y * c.x;
    volume += (a.x * cx + a.y * cy + a.z * cz) / 6.0f;
  }
  return volume;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) return fail("expected fixture path argument");

  const auto result = brepsight::importThreeMf(argv[1]);
  if (!result.ok()) return fail(result.error.empty() ? "import returned no mesh" : result.error);
  if (!result.payload) return fail("payload missing");
  if (result.payload->modelUnit != "centimeter") return fail("model unit was not preserved");
  if (result.rootObjectCount != 2) return fail("expected 2 build roots");
  if (result.hierarchyNodeCount != 5) return fail("expected 5 expanded hierarchy nodes");
  if (result.payload->expandedObjectCount != 5) return fail("expanded object count mismatch");
  if (result.payload->buildItems.size() != 2) return fail("expected 2 build item records");

  const auto& nested = result.payload->buildItems[0];
  if (nested.resourceId != 3 || nested.name != "Nested" || nested.partNumber != "BUILD-NESTED") {
    return fail("nested build item metadata mismatch");
  }
  if (!nested.componentsObject || nested.meshObject) return fail("nested build item type mismatch");
  if (!near(nested.transform[9], 1.0f)) return fail("nested build translation mismatch");

  const auto& mirrored = result.payload->buildItems[1];
  if (mirrored.resourceId != 1 || mirrored.name != "Tetra" || mirrored.partNumber != "BUILD-MESH") {
    return fail("mirrored build item metadata mismatch");
  }
  if (!mirrored.meshObject || mirrored.componentsObject) return fail("mirrored build item type mismatch");
  if (!near(mirrored.transform[0], -1.0f) || !near(mirrored.transform[9], 8.0f)) {
    return fail("mirrored build transform mismatch");
  }

  const auto& mesh = *result.displayMesh;
  if (mesh.sourceFormat != "3mf") return fail("source format mismatch");
  if (mesh.triangleCount != 12) return fail("expected 12 expanded triangles");
  if (mesh.vertices.size() != 36) return fail("expected 36 expanded vertices");
  if (!mesh.bounds.valid) return fail("bounds missing");

  if (!near(mesh.bounds.min.x, 10.0f) || !near(mesh.bounds.min.y, 0.0f) || !near(mesh.bounds.min.z, 0.0f) ||
      !near(mesh.bounds.max.x, 80.0f) || !near(mesh.bounds.max.y, 40.0f) || !near(mesh.bounds.max.z, 10.0f)) {
    return fail("centimeter-to-millimeter transform/bounds mismatch");
  }

  if (!near(signedVolume(mesh), 500.0f, 0.1f)) {
    return fail("mirrored winding correction did not preserve positive signed volume");
  }

  std::cout << "3MF semantic fixture passed: roots=2 hierarchy=5 triangles=12 volume=500mm^3\n";
  return EXIT_SUCCESS;
}
