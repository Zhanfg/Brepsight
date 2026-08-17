#include "freecad_presentation_adapter.h"

#include <cstdint>
#include <utility>

#include "mesh_presentation.h"

namespace brepsight {
namespace {

Vec3 unpackFreeCadShapeColor(std::uint32_t packed) {
  constexpr float kScale = 1.0f / 255.0f;
  return {
      static_cast<float>((packed >> 24) & 0xFFu) * kScale,
      static_cast<float>((packed >> 16) & 0xFFu) * kScale,
      static_cast<float>((packed >> 8) & 0xFFu) * kScale,
  };
}

}  // namespace

bool attachFcStdObjectPresentation(FcStdImportResult& fcstd, std::string& error) {
  error.clear();
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

}  // namespace brepsight
