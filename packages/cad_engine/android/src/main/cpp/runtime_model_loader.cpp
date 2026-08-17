#include "runtime_model_loader.h"

#include <algorithm>
#include <cctype>
#include <cstdint>

#include "brep_occt_importer.h"
#include "freecad_fcstd_importer.h"
#include "mesh_presentation.h"
#include "obj_importer.h"
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

Vec3 unpackFreeCadShapeColor(std::uint32_t packed) {
  constexpr float kScale = 1.0f / 255.0f;
  return {
      static_cast<float>((packed >> 24) & 0xFFu) * kScale,
      static_cast<float>((packed >> 16) & 0xFFu) * kScale,
      static_cast<float>((packed >> 8) & 0xFFu) * kScale,
  };
}

bool attachFcStdObjectPresentation(FcStdImportResult& fcstd, std::string& error) {
  if (fcstd.displayMesh == nullptr || fcstd.payload == nullptr) return true;

  auto& presentation = fcstd.displayMesh->objectPresentation;
  presentation.clear();
  presentation.reserve(fcstd.payload->objects.size());
  for (const FcStdObjectPayload& source : fcstd.payload->objects) {
    MeshObjectPresentation object;
    object.objectId = source.name;
    object.label = source.label;
    object.type = source.type;
    object.parentObjectId = source.parentName;
    object.visible = !source.hasVisibility || source.visible;
    object.effectiveVisible = object.visible;
    if (source.hasShapeColor) {
      object.hasBaseColor = true;
      object.baseColor = unpackFreeCadShapeColor(source.shapeColor);
    }
    presentation.push_back(std::move(object));
  }
  return refreshMeshPresentation(*fcstd.displayMesh, error);
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
