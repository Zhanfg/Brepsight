#include "runtime_model_loader.h"

#include <algorithm>
#include <cctype>

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

  result.error = "No native runtime provider is connected for this format yet.";
  return result;
}

}  // namespace brepsight
