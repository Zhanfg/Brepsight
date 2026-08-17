#include "mesh_presentation.h"

#include <algorithm>
#include <cstddef>
#include <iomanip>
#include <limits>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace brepsight {
namespace {

constexpr std::size_t kMaxPresentationDepth = 512;

std::string jsonEscape(const std::string& value) {
  std::ostringstream out;
  out << '"';
  for (unsigned char ch : value) {
    switch (ch) {
      case '"': out << "\\\""; break;
      case '\\': out << "\\\\"; break;
      case '\b': out << "\\b"; break;
      case '\f': out << "\\f"; break;
      case '\n': out << "\\n"; break;
      case '\r': out << "\\r"; break;
      case '\t': out << "\\t"; break;
      default:
        if (ch < 0x20) {
          out << "\\u00" << std::hex << std::uppercase << std::setw(2)
              << std::setfill('0') << static_cast<int>(ch)
              << std::dec << std::nouppercase << std::setfill(' ');
        } else {
          out << static_cast<char>(ch);
        }
    }
  }
  out << '"';
  return out.str();
}

bool resolveEffectiveVisibility(
    std::size_t index,
    std::vector<MeshObjectPresentation>& objects,
    const std::unordered_map<std::string, std::size_t>& indexById,
    std::vector<unsigned char>& states,
    std::size_t depth,
    std::string& error) {
  if (depth > kMaxPresentationDepth) {
    error = "Object presentation hierarchy exceeds the depth safety limit.";
    return false;
  }
  if (states[index] == 2) return true;
  if (states[index] == 1) {
    error = "Object presentation hierarchy contains a parent cycle.";
    return false;
  }
  states[index] = 1;

  MeshObjectPresentation& object = objects[index];
  bool effective = object.visible;
  if (!object.parentObjectId.empty()) {
    const auto parentIt = indexById.find(object.parentObjectId);
    if (parentIt == indexById.end()) {
      error = "Object presentation hierarchy references a missing parent.";
      return false;
    }
    if (!resolveEffectiveVisibility(
            parentIt->second,
            objects,
            indexById,
            states,
            depth + 1,
            error)) {
      return false;
    }
    effective = effective && objects[parentIt->second].effectiveVisible;
  }

  object.effectiveVisible = effective;
  states[index] = 2;
  return true;
}

}  // namespace

bool refreshMeshPresentation(MeshData& mesh, std::string& error) {
  error.clear();
  if (mesh.objectPresentation.empty()) {
    // Providers without object state keep their original bounds/range state.
    return true;
  }

  std::unordered_map<std::string, std::size_t> indexById;
  indexById.reserve(mesh.objectPresentation.size());
  for (std::size_t index = 0; index < mesh.objectPresentation.size(); ++index) {
    MeshObjectPresentation& object = mesh.objectPresentation[index];
    if (object.objectId.empty()) {
      error = "Object presentation contains an empty object id.";
      return false;
    }
    if (!indexById.emplace(object.objectId, index).second) {
      error = "Object presentation contains duplicate object ids.";
      return false;
    }
    object.hasGeometry = false;
  }

  std::vector<unsigned char> states(mesh.objectPresentation.size(), 0);
  for (std::size_t index = 0; index < mesh.objectPresentation.size(); ++index) {
    if (!resolveEffectiveVisibility(
            index,
            mesh.objectPresentation,
            indexById,
            states,
            0,
            error)) {
      return false;
    }
  }

  Bounds3 visibleBounds;
  for (MeshDrawRange& range : mesh.drawRanges) {
    if (range.vertexCount == 0) continue;
    if (range.firstVertex > mesh.vertices.size() ||
        range.vertexCount > mesh.vertices.size() - range.firstVertex) {
      error = "Object presentation draw range is outside the vertex buffer.";
      return false;
    }

    if (!range.sourceObject.empty()) {
      const auto objectIt = indexById.find(range.sourceObject);
      if (objectIt == indexById.end()) {
        error = "Object presentation draw range references an unknown object.";
        return false;
      }
      MeshObjectPresentation& object = mesh.objectPresentation[objectIt->second];
      object.hasGeometry = true;
      range.visible = object.effectiveVisible;
      if (object.hasBaseColor) {
        range.hasBaseColor = true;
        range.baseColor = object.baseColor;
      }
    }

    if (!range.visible) continue;
    for (std::size_t vertexIndex = range.firstVertex;
         vertexIndex < range.firstVertex + range.vertexCount;
         ++vertexIndex) {
      visibleBounds.include(mesh.vertices[vertexIndex].position);
    }
  }

  mesh.bounds = visibleBounds;
  return true;
}

bool setMeshObjectVisibility(
    MeshData& mesh,
    const std::string& objectId,
    bool visible,
    std::string& error) {
  error.clear();
  auto objectIt = std::find_if(
      mesh.objectPresentation.begin(),
      mesh.objectPresentation.end(),
      [&](const MeshObjectPresentation& object) {
        return object.objectId == objectId;
      });
  if (objectIt == mesh.objectPresentation.end()) {
    error = "Unknown object presentation id: " + objectId;
    return false;
  }

  // Visibility changes are transactional. refreshMeshPresentation() validates
  // the full provider-neutral hierarchy and draw-range graph and may touch
  // effective state before discovering a later malformed edge/range. Snapshot
  // only presentation metadata/ranges/bounds (never the vertex buffer or exact
  // provider payload) so a failed mutation cannot leave a half-updated document.
  std::vector<MeshObjectPresentation> previousPresentation = mesh.objectPresentation;
  std::vector<MeshDrawRange> previousRanges = mesh.drawRanges;
  const Bounds3 previousBounds = mesh.bounds;

  objectIt->visible = visible;
  if (refreshMeshPresentation(mesh, error)) return true;

  mesh.objectPresentation = std::move(previousPresentation);
  mesh.drawRanges = std::move(previousRanges);
  mesh.bounds = previousBounds;
  return false;
}

std::string meshObjectPresentationJson(const MeshData& mesh) {
  std::ostringstream out;
  out << '[';
  for (std::size_t index = 0; index < mesh.objectPresentation.size(); ++index) {
    if (index != 0) out << ',';
    const MeshObjectPresentation& object = mesh.objectPresentation[index];
    out << '{'
        << "\"id\":" << jsonEscape(object.objectId) << ','
        << "\"label\":" << jsonEscape(object.label) << ','
        << "\"type\":" << jsonEscape(object.type) << ','
        << "\"parentId\":" << jsonEscape(object.parentObjectId) << ','
        << "\"visible\":" << (object.visible ? "true" : "false") << ','
        << "\"effectiveVisible\":" << (object.effectiveVisible ? "true" : "false") << ','
        << "\"hasGeometry\":" << (object.hasGeometry ? "true" : "false") << ','
        << "\"hasBaseColor\":" << (object.hasBaseColor ? "true" : "false") << ','
        << "\"baseColor\":["
        << std::setprecision(9) << object.baseColor.x << ','
        << std::setprecision(9) << object.baseColor.y << ','
        << std::setprecision(9) << object.baseColor.z << ']'
        << '}';
  }
  out << ']';
  return out.str();
}

}  // namespace brepsight
