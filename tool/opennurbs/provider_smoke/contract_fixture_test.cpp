#include <cmath>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

#include <opennurbs_public.h>

#include "rhino_3dm_importer.h"

namespace {

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

ON_3dmObjectAttributes* attributes() {
  auto* value = new ON_3dmObjectAttributes();
  value->m_layer_index = 0;
  value->m_name = L"BrepSight 0.1 mesh fixture";
  return value;
}

void writeFixture(const std::filesystem::path& path) {
  ON::Begin();

  ONX_Model model;
  model.m_sStartSectionComments = "BrepSight 0.1 openNURBS contract fixture";
  model.AddDefaultLayer(L"fixture", ON_Color::Black);

  auto* mesh = new ON_Mesh();
  mesh->m_V.Append(ON_3fPoint(0.0f, 0.0f, 0.0f));
  mesh->m_V.Append(ON_3fPoint(2.0f, 0.0f, 0.0f));
  mesh->m_V.Append(ON_3fPoint(0.0f, 3.0f, 0.0f));
  mesh->m_V.Append(ON_3fPoint(0.0f, 0.0f, 4.0f));

  ON_MeshFace first{};
  first.vi[0] = 0;
  first.vi[1] = 1;
  first.vi[2] = 2;
  first.vi[3] = 2;
  mesh->m_F.Append(first);

  ON_MeshFace second{};
  second.vi[0] = 0;
  second.vi[1] = 1;
  second.vi[2] = 3;
  second.vi[3] = 3;
  mesh->m_F.Append(second);

  mesh->ComputeFaceNormals();
  mesh->ComputeVertexNormals();
  require(mesh->IsValid(), "generated openNURBS mesh is invalid");

  model.AddManagedModelGeometryComponent(mesh, attributes());
  ON_TextLog log;
  const ON_wString widePath(path.string().c_str());
  require(model.Write(widePath, 0, &log), "failed to write generated .3dm fixture");
}

}  // namespace

int main(int argc, char** argv) {
  try {
    const std::filesystem::path fixture =
        argc > 1 ? std::filesystem::path(argv[1]) : std::filesystem::path("brepsight-contract.3dm");
    writeFixture(fixture);

    const brepsight::Rhino3dmImportResult result =
        brepsight::importRhino3dm(fixture.string());
    require(result.error.empty(), "3DM importer returned: " + result.error);
    require(result.displayMesh != nullptr, "3DM importer produced no display mesh");
    require(result.payload != nullptr, "3DM importer produced no provider payload");
    require(result.displayMesh->sourceFormat == "3dm", "source format identity changed");
    require(result.displayMesh->triangleCount == 2, "fixture should import exactly two triangles");
    require(result.displayMesh->vertices.size() == 6, "fixture should emit exactly six triangle vertices");
    require(result.displayMesh->bounds.valid, "3DM bounds are invalid");
    require(result.displayMesh->bounds.max.x >= 1.99f, "3DM X extent was lost");
    require(result.displayMesh->bounds.max.y >= 2.99f, "3DM Y extent was lost");
    require(result.displayMesh->bounds.max.z >= 3.99f, "3DM Z extent was lost");
    require(result.payload->geometryObjectCount == 1, "geometry object count changed");
    require(result.payload->renderMeshObjectCount == 1, "saved render mesh was not consumed");
    require(result.rootObjectCount == 1, "root object identity changed");
    require(result.hierarchyNodeCount == 1, "3DM hierarchy count changed");
    require(result.displayMesh->drawRanges.size() == 1, "3DM draw range was not preserved");
    require(
        result.displayMesh->drawRanges.front().sourceObject == "rhino/0",
        "3DM stable object identity changed");

    std::cout << "openNURBS 3DM saved-mesh contract passed.\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "openNURBS 3DM saved-mesh contract failed: " << error.what() << '\n';
    return 1;
  }
}
