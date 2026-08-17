#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include "assimp_dcc_importer.h"

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

void writeText(const fs::path& path, const std::string& content) {
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  require(static_cast<bool>(out), "could not create fixture: " + path.string());
  out << content;
  out.close();
  require(fs::is_regular_file(path) && fs::file_size(path) > 0, "fixture was not written: " + path.string());
}

const brepsight::AssimpNodeInfo& findNode(
    const brepsight::AssimpDccPayload& payload,
    const std::string& name) {
  for (const auto& node : payload.nodes) {
    if (node.name == name) return node;
  }
  throw std::runtime_error("missing imported node: " + name);
}

const brepsight::MeshObjectPresentation& findPresentation(
    const brepsight::MeshData& mesh,
    const std::string& id) {
  for (const auto& object : mesh.objectPresentation) {
    if (object.objectId == id) return object;
  }
  throw std::runtime_error("missing object presentation: " + id);
}

const brepsight::MeshDrawRange& findRange(
    const brepsight::MeshData& mesh,
    const std::string& id) {
  for (const auto& range : mesh.drawRanges) {
    if (range.sourceObject == id) return range;
  }
  throw std::runtime_error("missing draw range for object: " + id);
}

void verifyDae(const fs::path& path) {
  const auto imported = brepsight::importDccWithAssimp(path.string(), "dae");
  require(imported.ok(), "DAE provider failed: " + imported.error);
  require(imported.payload->sourceFormat == "dae", "DAE payload source format mismatch");
  require(imported.rootObjectCount == 1, "DAE should expose one Assimp scene root");
  require(imported.hierarchyNodeCount >= 3, "DAE hierarchy should preserve root/child/camera nodes");
  require(imported.displayMesh->triangleCount == 1, "DAE triangle count mismatch");
  require(imported.displayMesh->hasNormals, "DAE display mesh should expose normals");
  require(imported.displayMesh->bounds.valid, "DAE visible bounds are invalid");

  // Root x=10 + Child x=5 => triangle world x range 15..17.
  requireNear(imported.displayMesh->bounds.min.x, 15.0, 1.0e-4, "DAE world min.x");
  requireNear(imported.displayMesh->bounds.max.x, 17.0, 1.0e-4, "DAE world max.x");
  requireNear(imported.displayMesh->bounds.min.y, 0.0, 1.0e-4, "DAE world min.y");
  requireNear(imported.displayMesh->bounds.max.y, 3.0, 1.0e-4, "DAE world max.y");

  const auto& root = findNode(*imported.payload, "Root");
  const auto& child = findNode(*imported.payload, "Child");
  require(child.parentId == root.id, "DAE Child parent relation was not preserved");
  requireNear(root.localTransform[3], 10.0, 1.0e-8, "DAE Root local tx");
  requireNear(child.localTransform[3], 5.0, 1.0e-8, "DAE Child local tx");
  require(child.meshIndices.size() == 1, "DAE Child should reference one mesh");

  const auto& childPresentation = findPresentation(*imported.displayMesh, child.id);
  require(childPresentation.parentObjectId == root.id, "DAE generic presentation parent mismatch");
  require(childPresentation.hasGeometry, "DAE Child presentation should be geometry-bearing");
  require(childPresentation.visible && childPresentation.effectiveVisible, "DAE Child should start visible");

  const auto& range = findRange(*imported.displayMesh, child.id);
  require(range.vertexCount == 3, "DAE draw range should contain one triangle");
  require(range.hasBaseColor, "DAE material diffuse color was not propagated to draw range");
  requireNear(range.baseColor.x, 0.2, 1.0e-4, "DAE diffuse red");
  requireNear(range.baseColor.y, 0.4, 1.0e-4, "DAE diffuse green");
  requireNear(range.baseColor.z, 0.6, 1.0e-4, "DAE diffuse blue");

  bool foundMaterial = false;
  for (const auto& material : imported.payload->materials) {
    if (material.hasDiffuseColor &&
        std::fabs(material.diffuseColor.x - 0.2f) < 1.0e-4f &&
        std::fabs(material.diffuseColor.y - 0.4f) < 1.0e-4f &&
        std::fabs(material.diffuseColor.z - 0.6f) < 1.0e-4f) {
      foundMaterial = true;
      break;
    }
  }
  require(foundMaterial, "DAE payload did not preserve the diffuse material");
  require(imported.payload->cameraCount == 1, "DAE camera metadata count mismatch");
  require(!imported.payload->warnings.empty(), "DAE partial camera support should produce a warning");
}

void verifyPly(const fs::path& path) {
  const auto imported = brepsight::importDccWithAssimp(path.string(), "ply");
  require(imported.ok(), "PLY provider failed: " + imported.error);
  require(imported.payload->sourceFormat == "ply", "PLY payload source format mismatch");
  require(imported.displayMesh->triangleCount == 1, "PLY triangle count mismatch");
  require(imported.displayMesh->bounds.valid, "PLY bounds invalid");
  requireNear(imported.displayMesh->bounds.max.x, 2.0, 1.0e-4, "PLY max.x");
  requireNear(imported.displayMesh->bounds.max.y, 2.0, 1.0e-4, "PLY max.y");
}

void verifyOff(const fs::path& path) {
  const auto imported = brepsight::importDccWithAssimp(path.string(), "off");
  require(imported.ok(), "OFF provider failed: " + imported.error);
  require(imported.payload->sourceFormat == "off", "OFF payload source format mismatch");
  require(imported.displayMesh->triangleCount == 1, "OFF triangle count mismatch");
  require(imported.displayMesh->bounds.valid, "OFF bounds invalid");
  requireNear(imported.displayMesh->bounds.max.x, 4.0, 1.0e-4, "OFF max.x");
  requireNear(imported.displayMesh->bounds.max.y, 1.0, 1.0e-4, "OFF max.y");
}

}  // namespace

int main() {
  try {
    const fs::path root = fs::current_path() / ".build" / "assimp-host-semantic";
    fs::remove_all(root);
    fs::create_directories(root);

    const fs::path daePath = root / "hierarchy-material-camera.dae";
    const fs::path plyPath = root / "triangle.ply";
    const fs::path offPath = root / "triangle.off";

    writeText(daePath, R"DAE(<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
  <asset>
    <contributor><authoring_tool>BrepSight clean-room semantic fixture</authoring_tool></contributor>
    <created>2026-08-17T00:00:00Z</created>
    <modified>2026-08-17T00:00:00Z</modified>
    <unit name="meter" meter="1"/>
    <up_axis>Y_UP</up_axis>
  </asset>
  <library_cameras>
    <camera id="fixture-camera" name="FixtureCamera">
      <optics><technique_common><perspective>
        <yfov sid="yfov">45</yfov>
        <aspect_ratio>1.5</aspect_ratio>
        <znear sid="znear">0.1</znear>
        <zfar sid="zfar">100</zfar>
      </perspective></technique_common></optics>
    </camera>
  </library_cameras>
  <library_effects>
    <effect id="material-fx">
      <profile_COMMON><technique sid="common"><lambert>
        <emission><color>0 0 0 1</color></emission>
        <diffuse><color>0.2 0.4 0.6 1</color></diffuse>
      </lambert></technique></profile_COMMON>
    </effect>
  </library_effects>
  <library_materials>
    <material id="fixture-material" name="FixtureMaterial">
      <instance_effect url="#material-fx"/>
    </material>
  </library_materials>
  <library_geometries>
    <geometry id="triangle-geometry" name="TriangleGeometry">
      <mesh>
        <source id="triangle-positions">
          <float_array id="triangle-positions-array" count="9">0 0 0 2 0 0 0 3 0</float_array>
          <technique_common><accessor source="#triangle-positions-array" count="3" stride="3">
            <param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/>
          </accessor></technique_common>
        </source>
        <vertices id="triangle-vertices"><input semantic="POSITION" source="#triangle-positions"/></vertices>
        <triangles material="fixture-symbol" count="1">
          <input semantic="VERTEX" source="#triangle-vertices" offset="0"/>
          <p>0 1 2</p>
        </triangles>
      </mesh>
    </geometry>
  </library_geometries>
  <library_visual_scenes>
    <visual_scene id="Scene" name="Scene">
      <node id="Root" name="Root" type="NODE">
        <translate>10 0 0</translate>
        <node id="Child" name="Child" type="NODE">
          <translate>5 0 0</translate>
          <instance_geometry url="#triangle-geometry">
            <bind_material><technique_common>
              <instance_material symbol="fixture-symbol" target="#fixture-material"/>
            </technique_common></bind_material>
          </instance_geometry>
        </node>
      </node>
      <node id="CameraNode" name="CameraNode" type="NODE">
        <translate>0 0 8</translate>
        <instance_camera url="#fixture-camera"/>
      </node>
    </visual_scene>
  </library_visual_scenes>
  <scene><instance_visual_scene url="#Scene"/></scene>
</COLLADA>
)DAE");

    writeText(plyPath, R"PLY(ply
format ascii 1.0
comment BrepSight clean-room fixture
element vertex 3
property float x
property float y
property float z
element face 1
property list uchar int vertex_indices
end_header
0 0 0
2 0 0
0 2 0
3 0 1 2
)PLY");

    writeText(offPath, R"OFF(OFF
3 1 0
0 0 0
4 0 0
0 1 0
3 0 1 2
)OFF");

    verifyDae(daePath);
    verifyPly(plyPath);
    verifyOff(offPath);

    const auto rejected = brepsight::importDccWithAssimp(daePath.string(), "blend");
    require(!rejected.ok(), "BLEND policy guard should reject the unvalidated source format id");

    std::cout
        << "Assimp DCC semantic smoke passed: clean-room DAE hierarchy/transform/material/camera warning and PLY/OFF geometry verified.\n";
    fs::remove_all(root);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "Assimp DCC semantic smoke failure: " << error.what() << '\n';
    return 1;
  }
}
