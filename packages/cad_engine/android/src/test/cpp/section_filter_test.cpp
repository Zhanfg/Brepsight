#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

#include "section_filter.h"

namespace {

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

brepsight::MeshVertex vertex(float x, float y, float z) {
  return {
      brepsight::Vec3{x, y, z},
      brepsight::Vec3{0.0f, 0.0f, 1.0f},
      brepsight::Vec3{},
      brepsight::Vec2{},
  };
}

}  // namespace

int main() {
  try {
    brepsight::MeshData mesh;
    mesh.sourceFormat = "fixture";
    mesh.vertices = {
        vertex(-1.0f, 0.0f, -1.0f),
        vertex(1.0f, 0.0f, 1.0f),
        vertex(0.0f, 1.0f, 1.0f),
    };
    mesh.triangleCount = 1;
    brepsight::MeshDrawRange range;
    range.firstVertex = 0;
    range.vertexCount = 3;
    range.visible = true;
    range.sourceObject = "fixture/object";
    mesh.drawRanges.push_back(range);

    std::string error;
    require(
        brepsight::setActiveSectionPlane(
            true,
            brepsight::Vec3{0.0f, 0.0f, 1.0f},
            0.0f,
            error),
        "could not set section plane: " + error);
    require(brepsight::applyActiveSectionPlane(mesh, error), "clip failed: " + error);
    require(mesh.triangleCount == 2, "crossing triangle should be split into two triangles");
    require(mesh.vertices.size() == 6, "clipped triangle should emit six vertices");
    require(mesh.bounds.valid, "clipped bounds should be valid");
    require(mesh.bounds.min.z >= -1.0e-5f, "clipped output crossed the retained half-space");
    require(mesh.drawRanges.size() == 1, "draw range should be preserved");
    require(mesh.drawRanges[0].sourceObject == "fixture/object", "draw-range object identity changed");
    require(mesh.drawRanges[0].vertexCount == 6, "draw-range count did not follow clipping");

    require(
        brepsight::setActiveSectionPlane(
            false,
            brepsight::Vec3{0.0f, 0.0f, 1.0f},
            0.0f,
            error),
        "could not disable section plane");

    std::cout << "Section filter test passed.\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "Section filter test failed: " << error.what() << '\n';
    return 1;
  }
}
