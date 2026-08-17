#include "runtime_model_loader.h"

#include <algorithm>
#include <cctype>

#include "assimp_dcc_importer.h"
#include "brep_occt_importer.h"
#include "freecad_fcstd_importer.h"
#include "freecad_presentation_adapter.h"
#include "iges_occt_importer.h"
#include "obj_importer.h"
#include "rhino_3dm_importer.h"
#include "step_occt_importer.h"
#include "stl_importer.h"
#include "three_mf_importer.h"

namespace brepsight {
namespace {

std::string lowercaseExtension(const std::string& path) {
  const auto slash = path.find_last_of("/\\");
  const auto dot = path.find_last_of('.');
  if (dot == std::string::npos ||
      (slash != std::string::npos && dot < slash)) {
    return {};
  }
  std::string extension = path.substr(dot + 1);
  std::transform(
      extension.begin(), extension.end(), extension.begin(),
      [](unsigned char value) { return static_cast<char>(std::tolower(value)); });
  return extension;
}

bool isAssimpBaselineFormat(const std::string& extension) {
  return extension == "fbx" || extension == "dae" || extension == "ply" ||
      extension == "off" || extension == "gltf" || extension == "glb" ||
      extension == "3ds" || extension == "dxf";
}

bool isOriginalAssimpValidatedToken(const std::string& extension) {
  return extension == "fbx" || extension == "dae" ||
      extension == "ply" || extension == "off";
}

}  // namespace

RuntimeLoadResult loadRuntimeModel(const std::string& path) {
  RuntimeLoadResult result;
  const std::string extension = lowercaseExtension(path);

  if (extension == "stl") {
    auto mesh = std::make_shared<MeshData>();
    if (!loadStl(path, *mesh, result.error)) return result;
    result.mesh = std::move(mesh);
    result.formatId = "stl";
    return result;
  }

  if (extension == "obj") {
    auto mesh = std::make_shared<MeshData>();
    if (!loadObj(path, *mesh, result.error)) return result;
    result.mesh = std::move(mesh);
    result.formatId = "obj";
    return result;
  }

  if (isAssimpBaselineFormat(extension)) {
    const std::string providerToken =
        isOriginalAssimpValidatedToken(extension) ? extension : "dae";
    AssimpDccImportResult dcc = importDccWithAssimp(path, providerToken);
    if (dcc.displayMesh != nullptr) dcc.displayMesh->sourceFormat = extension;
    if (dcc.payload != nullptr) dcc.payload->sourceFormat = extension;
    result.mesh = std::move(dcc.displayMesh);
    result.providerPayload = std::move(dcc.payload);
    result.formatId = extension;
    result.error = std::move(dcc.error);
    result.exactGeometry = false;
    result.rootObjectCount = dcc.rootObjectCount;
    result.hierarchyNodeCount = dcc.hierarchyNodeCount;
    return result;
  }

  if (extension == "brep" || extension == "brp") {
    BrepOcctImportResult brep = importBrepWithOcct(path);
    result.mesh = std::move(brep.displayMesh);
    result.providerPayload = std::move(brep.exactPayload);
    result.formatId = "brep";
    result.error = std::move(brep.error);
    result.exactGeometry = result.providerPayload != nullptr;
    result.rootObjectCount = result.exactGeometry ? 1 : 0;
    result.hierarchyNodeCount = result.rootObjectCount;
    return result;
  }

  if (extension == "step" || extension == "stp") {
    StepOcctImportResult step = importStepWithOcct(path);
    result.mesh = std::move(step.displayMesh);
    result.providerPayload = std::move(step.exactPayload);
    result.formatId = "step";
    result.error = std::move(step.error);
    result.exactGeometry = result.providerPayload != nullptr;
    result.rootObjectCount = step.rootShapeCount;
    result.hierarchyNodeCount = step.assemblyNodeCount;
    return result;
  }

  if (extension == "iges" || extension == "igs") {
    IgesOcctImportResult iges = importIgesWithOcct(path);
    result.mesh = std::move(iges.displayMesh);
    result.providerPayload = std::move(iges.exactPayload);
    result.formatId = "iges";
    result.error = std::move(iges.error);
    result.exactGeometry = result.providerPayload != nullptr;
    result.rootObjectCount = iges.rootShapeCount;
    result.hierarchyNodeCount = iges.hierarchyNodeCount;
    return result;
  }

  if (extension == "3dm") {
    Rhino3dmImportResult rhino = importRhino3dm(path);
    result.mesh = std::move(rhino.displayMesh);
    result.providerPayload = std::move(rhino.payload);
    result.formatId = "3dm";
    result.error = std::move(rhino.error);
    result.exactGeometry = false;
    result.rootObjectCount = rhino.rootObjectCount;
    result.hierarchyNodeCount = rhino.hierarchyNodeCount;
    return result;
  }

  if (extension == "3mf") {
    ThreeMfImportResult threeMf = importThreeMf(path);
    result.mesh = std::move(threeMf.displayMesh);
    result.providerPayload = std::move(threeMf.payload);
    result.formatId = "3mf";
    result.error = std::move(threeMf.error);
    result.exactGeometry = false;
    result.rootObjectCount = threeMf.rootObjectCount;
    result.hierarchyNodeCount = threeMf.hierarchyNodeCount;
    return result;
  }

  if (extension == "fcstdmanifest") {
    FcStdImportResult fcstd = importPreparedFcStd(path);
    if (fcstd.ok() && !attachFcStdObjectPresentation(fcstd, result.error)) {
      result.error = "FCStd presentation state is invalid: " + result.error;
      return result;
    }
    result.mesh = std::move(fcstd.displayMesh);
    result.providerPayload = std::move(fcstd.payload);
    result.formatId = "fcstd";
    if (result.error.empty()) result.error = std::move(fcstd.error);
    result.sourcePathOverride = std::move(fcstd.sourcePathOverride);
    result.exactGeometry = result.providerPayload != nullptr;
    result.rootObjectCount = fcstd.rootObjectCount;
    result.hierarchyNodeCount = fcstd.hierarchyNodeCount;
    return result;
  }

  result.error = "No native runtime provider is connected for this format yet.";
  return result;
}

}  // namespace brepsight
