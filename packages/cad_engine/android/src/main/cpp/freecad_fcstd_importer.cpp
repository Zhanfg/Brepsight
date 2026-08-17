#include "freecad_fcstd_importer.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "brep_occt_importer.h"

namespace brepsight {
namespace {

constexpr const char* kManifestHeader = "BREPSIGHT_FCSTD_V2";
constexpr std::size_t kMaxManifestBytes = 32 * 1024 * 1024;
constexpr std::size_t kMaxShapeRecords = 10000;
constexpr std::size_t kMaxDocumentObjects = 1000000;
constexpr std::size_t kMaxGroupEdges = 100000;
constexpr std::size_t kMaxHierarchyDepth = 512;

struct ShapeRecord {
  std::string objectName;
  std::string extractedPath;
};

struct ParsedObject {
  FcStdObjectPayload payload;
  bool presentationSeen = false;
  bool effectiveVisible = true;
  int resolutionState = 0;
  int visibilityResolutionState = 0;
};

int hexValue(char value) {
  if (value >= '0' && value <= '9') return value - '0';
  if (value >= 'a' && value <= 'f') return 10 + value - 'a';
  if (value >= 'A' && value <= 'F') return 10 + value - 'A';
  return -1;
}

bool percentDecode(const std::string& encoded, std::string& decoded) {
  decoded.clear();
  decoded.reserve(encoded.size());
  for (std::size_t index = 0; index < encoded.size(); ++index) {
    const char value = encoded[index];
    if (value != '%') {
      if (value == '\0') return false;
      decoded.push_back(value);
      continue;
    }
    if (index + 2 >= encoded.size()) return false;
    const int high = hexValue(encoded[index + 1]);
    const int low = hexValue(encoded[index + 2]);
    if (high < 0 || low < 0) return false;
    const char decodedByte = static_cast<char>((high << 4) | low);
    if (decodedByte == '\0') return false;
    decoded.push_back(decodedByte);
    index += 2;
  }
  return true;
}

std::vector<std::string> splitTabs(const std::string& line) {
  std::vector<std::string> fields;
  std::size_t start = 0;
  while (true) {
    const std::size_t tab = line.find('\t', start);
    if (tab == std::string::npos) {
      fields.push_back(line.substr(start));
      break;
    }
    fields.push_back(line.substr(start, tab - start));
    start = tab + 1;
  }
  return fields;
}

bool parseCount(const std::string& value, std::size_t maximum, std::size_t& output) {
  if (value.empty() || value.size() > 20 ||
      !std::all_of(value.begin(), value.end(), [](unsigned char ch) { return std::isdigit(ch) != 0; })) {
    return false;
  }
  try {
    const unsigned long long parsed = std::stoull(value);
    if (parsed > maximum) return false;
    output = static_cast<std::size_t>(parsed);
    return true;
  } catch (...) {
    return false;
  }
}

bool parseFiniteDouble(const std::string& value, double& output) {
  if (value.empty() || value.size() > 64) return false;
  try {
    std::size_t consumed = 0;
    const double parsed = std::stod(value, &consumed);
    if (consumed != value.size() || !std::isfinite(parsed)) return false;
    output = parsed;
    return true;
  } catch (...) {
    return false;
  }
}

bool parseColor(const std::string& value, std::uint32_t& output) {
  if (value.empty() || value.size() > 10 ||
      !std::all_of(value.begin(), value.end(), [](unsigned char ch) { return std::isdigit(ch) != 0; })) {
    return false;
  }
  try {
    const unsigned long long parsed = std::stoull(value);
    if (parsed > std::numeric_limits<std::uint32_t>::max()) return false;
    output = static_cast<std::uint32_t>(parsed);
    return true;
  } catch (...) {
    return false;
  }
}

bool normalizeTransform(FcStdTransform& transform) {
  const double normSquared =
      transform.qx * transform.qx + transform.qy * transform.qy +
      transform.qz * transform.qz + transform.qw * transform.qw;
  if (!std::isfinite(normSquared) || normSquared < 1.0e-24) return false;
  const double inverseNorm = 1.0 / std::sqrt(normSquared);
  transform.qx *= inverseNorm;
  transform.qy *= inverseNorm;
  transform.qz *= inverseNorm;
  transform.qw *= inverseNorm;
  return std::isfinite(transform.tx) && std::isfinite(transform.ty) && std::isfinite(transform.tz) &&
      std::isfinite(transform.qx) && std::isfinite(transform.qy) &&
      std::isfinite(transform.qz) && std::isfinite(transform.qw);
}

std::array<double, 3> rotateVector(const FcStdTransform& transform, double x, double y, double z) {
  const double ux = transform.qx;
  const double uy = transform.qy;
  const double uz = transform.qz;
  const double s = transform.qw;
  const double crossX = uy * z - uz * y;
  const double crossY = uz * x - ux * z;
  const double crossZ = ux * y - uy * x;
  const double cross2X = uy * crossZ - uz * crossY;
  const double cross2Y = uz * crossX - ux * crossZ;
  const double cross2Z = ux * crossY - uy * crossX;
  return {
      x + 2.0 * (s * crossX + cross2X),
      y + 2.0 * (s * crossY + cross2Y),
      z + 2.0 * (s * crossZ + cross2Z),
  };
}

FcStdTransform composeTransforms(const FcStdTransform& parent, const FcStdTransform& local) {
  FcStdTransform result;
  const auto translated = rotateVector(parent, local.tx, local.ty, local.tz);
  result.tx = parent.tx + translated[0];
  result.ty = parent.ty + translated[1];
  result.tz = parent.tz + translated[2];

  result.qx = parent.qw * local.qx + parent.qx * local.qw + parent.qy * local.qz - parent.qz * local.qy;
  result.qy = parent.qw * local.qy - parent.qx * local.qz + parent.qy * local.qw + parent.qz * local.qx;
  result.qz = parent.qw * local.qz + parent.qx * local.qy - parent.qy * local.qx + parent.qz * local.qw;
  result.qw = parent.qw * local.qw - parent.qx * local.qx - parent.qy * local.qy - parent.qz * local.qz;
  if (!normalizeTransform(result)) throw std::runtime_error("FCStd composed placement is invalid.");
  return result;
}

Vec3 transformPoint(const FcStdTransform& transform, const Vec3& point) {
  const auto rotated = rotateVector(transform, point.x, point.y, point.z);
  const double x = rotated[0] + transform.tx;
  const double y = rotated[1] + transform.ty;
  const double z = rotated[2] + transform.tz;
  const float fx = static_cast<float>(x);
  const float fy = static_cast<float>(y);
  const float fz = static_cast<float>(z);
  if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z) ||
      !std::isfinite(fx) || !std::isfinite(fy) || !std::isfinite(fz)) {
    throw std::runtime_error("FCStd placement produced a non-finite display coordinate.");
  }
  return {fx, fy, fz};
}

Vec3 transformNormal(const FcStdTransform& transform, const Vec3& normal) {
  const auto rotated = rotateVector(transform, normal.x, normal.y, normal.z);
  const float x = static_cast<float>(rotated[0]);
  const float y = static_cast<float>(rotated[1]);
  const float z = static_cast<float>(rotated[2]);
  if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z)) {
    throw std::runtime_error("FCStd placement produced a non-finite display normal.");
  }
  return {x, y, z};
}

Vec3 unpackFreeCadShapeColor(std::uint32_t packed) {
  constexpr float kScale = 1.0f / 255.0f;
  return {
      static_cast<float>((packed >> 24) & 0xFFu) * kScale,
      static_cast<float>((packed >> 16) & 0xFFu) * kScale,
      static_cast<float>((packed >> 8) & 0xFFu) * kScale,
  };
}

void appendMesh(
    const MeshData& source,
    MeshData& destination,
    const FcStdTransform& transform,
    const FcStdObjectPayload& object,
    bool effectiveVisible) {
  if (source.vertices.size() > destination.vertices.max_size() - destination.vertices.size()) {
    throw std::runtime_error("FCStd display mesh exceeds addressable vertex capacity.");
  }

  const std::size_t firstVertex = destination.vertices.size();
  destination.vertices.reserve(destination.vertices.size() + source.vertices.size());
  for (const MeshVertex& sourceVertex : source.vertices) {
    MeshVertex vertex = sourceVertex;
    vertex.position = transformPoint(transform, sourceVertex.position);
    vertex.normal = transformNormal(transform, sourceVertex.normal);
    destination.vertices.push_back(vertex);
    if (effectiveVisible) destination.bounds.include(vertex.position);
  }

  MeshDrawRange range;
  range.firstVertex = firstVertex;
  range.vertexCount = source.vertices.size();
  range.visible = effectiveVisible;
  range.sourceObject = object.name;
  if (object.hasShapeColor) {
    range.hasBaseColor = true;
    range.baseColor = unpackFreeCadShapeColor(object.shapeColor);
  }
  destination.drawRanges.push_back(std::move(range));

  if (source.triangleCount > std::numeric_limits<std::size_t>::max() - destination.triangleCount) {
    throw std::runtime_error("FCStd triangle-count overflow.");
  }
  destination.triangleCount += source.triangleCount;
  destination.hasNormals = destination.hasNormals || source.hasNormals;
  destination.hasUv = destination.hasUv || source.hasUv;
}

bool resolveWorldTransform(
    std::size_t index,
    std::vector<ParsedObject>& objects,
    const std::unordered_map<std::string, std::size_t>& indexByName,
    const std::unordered_map<std::string, std::string>& parentByChild,
    std::size_t depth,
    std::string& error) {
  if (depth > kMaxHierarchyDepth) {
    error = "Prepared FCStd hierarchy exceeds the depth safety limit.";
    return false;
  }
  ParsedObject& object = objects[index];
  if (object.resolutionState == 2) return true;
  if (object.resolutionState == 1) {
    error = "Prepared FCStd hierarchy contains a parent cycle.";
    return false;
  }
  object.resolutionState = 1;

  const auto parentNameIt = parentByChild.find(object.payload.name);
  if (parentNameIt == parentByChild.end()) {
    object.payload.worldTransform = object.payload.localTransform;
  } else {
    const auto parentIndexIt = indexByName.find(parentNameIt->second);
    if (parentIndexIt == indexByName.end()) {
      error = "Prepared FCStd hierarchy references a missing parent object.";
      return false;
    }
    if (!resolveWorldTransform(parentIndexIt->second, objects, indexByName, parentByChild, depth + 1, error)) {
      return false;
    }
    object.payload.parentName = parentNameIt->second;
    object.payload.worldTransform = composeTransforms(
        objects[parentIndexIt->second].payload.worldTransform,
        object.payload.localTransform);
  }

  object.resolutionState = 2;
  return true;
}

bool resolveEffectiveVisibility(
    std::size_t index,
    std::vector<ParsedObject>& objects,
    const std::unordered_map<std::string, std::size_t>& indexByName,
    const std::unordered_map<std::string, std::string>& parentByChild,
    std::size_t depth,
    std::string& error) {
  if (depth > kMaxHierarchyDepth) {
    error = "Prepared FCStd visibility hierarchy exceeds the depth safety limit.";
    return false;
  }
  ParsedObject& object = objects[index];
  if (object.visibilityResolutionState == 2) return true;
  if (object.visibilityResolutionState == 1) {
    error = "Prepared FCStd visibility hierarchy contains a parent cycle.";
    return false;
  }
  object.visibilityResolutionState = 1;

  bool visible = !object.payload.hasVisibility || object.payload.visible;
  const auto parentNameIt = parentByChild.find(object.payload.name);
  if (parentNameIt != parentByChild.end()) {
    const auto parentIndexIt = indexByName.find(parentNameIt->second);
    if (parentIndexIt == indexByName.end()) {
      error = "Prepared FCStd visibility hierarchy references a missing parent object.";
      return false;
    }
    if (!resolveEffectiveVisibility(parentIndexIt->second, objects, indexByName, parentByChild, depth + 1, error)) {
      return false;
    }
    visible = visible && objects[parentIndexIt->second].effectiveVisible;
  }

  object.effectiveVisible = visible;
  object.visibilityResolutionState = 2;
  return true;
}

}  // namespace

FcStdImportResult importPreparedFcStd(const std::string& manifestPath) {
  FcStdImportResult result;
  try {
    std::ifstream stream(manifestPath, std::ios::binary);
    if (!stream) {
      result.error = "Prepared FCStd manifest could not be opened.";
      return result;
    }
    stream.seekg(0, std::ios::end);
    const std::streamoff size = stream.tellg();
    if (size <= 0 || static_cast<unsigned long long>(size) > kMaxManifestBytes) {
      result.error = "Prepared FCStd manifest is empty or exceeds the safety limit.";
      return result;
    }
    stream.seekg(0, std::ios::beg);

    std::string header;
    if (!std::getline(stream, header) || header != kManifestHeader) {
      result.error = "Prepared FCStd manifest header is invalid.";
      return result;
    }

    std::string originalSource;
    std::size_t documentObjectCount = 0;
    bool objectCountSeen = false;
    std::vector<ParsedObject> objects;
    std::unordered_map<std::string, std::size_t> indexByName;
    std::unordered_map<std::string, std::string> parentByChild;
    std::vector<ShapeRecord> shapeRecords;
    std::size_t groupEdgeCount = 0;

    std::string line;
    while (std::getline(stream, line)) {
      if (line.empty()) continue;
      const std::vector<std::string> fields = splitTabs(line);
      if (fields.empty()) continue;

      if (fields[0] == "source") {
        if (fields.size() != 2 || !originalSource.empty() || !percentDecode(fields[1], originalSource)) {
          result.error = "Prepared FCStd source record is invalid.";
          return result;
        }
        continue;
      }

      if (fields[0] == "objects") {
        if (fields.size() != 2 || objectCountSeen ||
            !parseCount(fields[1], kMaxDocumentObjects, documentObjectCount)) {
          result.error = "Prepared FCStd object-count record is invalid.";
          return result;
        }
        objectCountSeen = true;
        continue;
      }

      if (fields[0] == "object") {
        if (fields.size() != 11 || objects.size() >= kMaxDocumentObjects) {
          result.error = "Prepared FCStd object record is invalid or exceeds the safety limit.";
          return result;
        }
        ParsedObject parsed;
        if (!percentDecode(fields[1], parsed.payload.name) || parsed.payload.name.empty() ||
            !percentDecode(fields[2], parsed.payload.type) ||
            !percentDecode(fields[3], parsed.payload.label) ||
            !parseFiniteDouble(fields[4], parsed.payload.localTransform.tx) ||
            !parseFiniteDouble(fields[5], parsed.payload.localTransform.ty) ||
            !parseFiniteDouble(fields[6], parsed.payload.localTransform.tz) ||
            !parseFiniteDouble(fields[7], parsed.payload.localTransform.qx) ||
            !parseFiniteDouble(fields[8], parsed.payload.localTransform.qy) ||
            !parseFiniteDouble(fields[9], parsed.payload.localTransform.qz) ||
            !parseFiniteDouble(fields[10], parsed.payload.localTransform.qw) ||
            !normalizeTransform(parsed.payload.localTransform)) {
          result.error = "Prepared FCStd object record encoding or placement is invalid.";
          return result;
        }
        parsed.payload.worldTransform = parsed.payload.localTransform;
        if (indexByName.find(parsed.payload.name) != indexByName.end()) {
          result.error = "Prepared FCStd manifest contains duplicate object records.";
          return result;
        }
        indexByName.emplace(parsed.payload.name, objects.size());
        objects.push_back(std::move(parsed));
        continue;
      }

      if (fields[0] == "presentation") {
        if (fields.size() != 4) {
          result.error = "Prepared FCStd presentation record is invalid.";
          return result;
        }
        std::string objectName;
        if (!percentDecode(fields[1], objectName) || objectName.empty()) {
          result.error = "Prepared FCStd presentation object encoding is invalid.";
          return result;
        }
        const auto objectIt = indexByName.find(objectName);
        if (objectIt == indexByName.end()) {
          result.error = "Prepared FCStd presentation references an unknown object.";
          return result;
        }
        ParsedObject& object = objects[objectIt->second];
        if (object.presentationSeen) {
          result.error = "Prepared FCStd manifest contains duplicate presentation records.";
          return result;
        }
        object.presentationSeen = true;
        if (fields[2] == "1") {
          object.payload.hasVisibility = true;
          object.payload.visible = true;
        } else if (fields[2] == "0") {
          object.payload.hasVisibility = true;
          object.payload.visible = false;
        } else if (fields[2] != "-") {
          result.error = "Prepared FCStd visibility record is invalid.";
          return result;
        }
        if (fields[3] != "-") {
          std::uint32_t color = 0;
          if (!parseColor(fields[3], color)) {
            result.error = "Prepared FCStd ShapeColor record is invalid.";
            return result;
          }
          object.payload.hasShapeColor = true;
          object.payload.shapeColor = color;
        }
        continue;
      }

      if (fields[0] == "group") {
        if (fields.size() != 3 || groupEdgeCount >= kMaxGroupEdges) {
          result.error = "Prepared FCStd group record is invalid or exceeds the safety limit.";
          return result;
        }
        std::string parent;
        std::string child;
        if (!percentDecode(fields[1], parent) || !percentDecode(fields[2], child) ||
            parent.empty() || child.empty() || parent == child ||
            indexByName.find(parent) == indexByName.end() || indexByName.find(child) == indexByName.end()) {
          result.error = "Prepared FCStd group record references an invalid object.";
          return result;
        }
        const auto existing = parentByChild.find(child);
        if (existing != parentByChild.end() && existing->second != parent) {
          result.error = "Prepared FCStd hierarchy gives one object multiple parents.";
          return result;
        }
        parentByChild[child] = parent;
        ++groupEdgeCount;
        continue;
      }

      if (fields[0] == "shape") {
        if (fields.size() != 3 || shapeRecords.size() >= kMaxShapeRecords) {
          result.error = "Prepared FCStd shape record is invalid or exceeds the safety limit.";
          return result;
        }
        ShapeRecord record;
        if (!percentDecode(fields[1], record.objectName) ||
            !percentDecode(fields[2], record.extractedPath) ||
            record.objectName.empty() || record.extractedPath.empty() ||
            indexByName.find(record.objectName) == indexByName.end()) {
          result.error = "Prepared FCStd shape record encoding or object reference is invalid.";
          return result;
        }
        shapeRecords.push_back(std::move(record));
        continue;
      }

      result.error = "Prepared FCStd manifest contains an unknown record type.";
      return result;
    }

    if (originalSource.empty() || !objectCountSeen || shapeRecords.empty() ||
        objects.size() != documentObjectCount) {
      result.error = "Prepared FCStd manifest is incomplete or object counts disagree.";
      return result;
    }

    for (std::size_t index = 0; index < objects.size(); ++index) {
      if (!resolveWorldTransform(index, objects, indexByName, parentByChild, 0, result.error) ||
          !resolveEffectiveVisibility(index, objects, indexByName, parentByChild, 0, result.error)) {
        return result;
      }
    }

    auto payload = std::make_shared<FcStdPayload>();
    payload->originalSourcePath = originalSource;
    payload->documentObjectCount = documentObjectCount;
    payload->objects.reserve(objects.size());
    for (const ParsedObject& object : objects) payload->objects.push_back(object.payload);

    auto merged = std::make_shared<MeshData>();
    merged->sourceFormat = "fcstd";

    std::string firstFailure;
    for (const ShapeRecord& record : shapeRecords) {
      BrepOcctImportResult imported = importBrepWithOcct(record.extractedPath);
      if (!imported.ok()) {
        ++payload->skippedShapeCount;
        if (firstFailure.empty()) firstFailure = imported.error;
        continue;
      }
      const ParsedObject& object = objects[indexByName.at(record.objectName)];
      appendMesh(
          *imported.displayMesh,
          *merged,
          object.payload.worldTransform,
          object.payload,
          object.effectiveVisible);
      payload->shapes.push_back(FcStdShapePayload{record.objectName, std::move(imported.exactPayload)});
    }

    if (payload->shapes.empty() || merged->vertices.empty()) {
      result.error = firstFailure.empty()
          ? "FCStd contained no readable saved BREP geometry."
          : "FCStd saved geometry could not be read: " + firstFailure;
      return result;
    }

    result.sourcePathOverride = originalSource;
    result.rootObjectCount = objects.size() - parentByChild.size();
    result.hierarchyNodeCount = objects.size();
    result.displayMesh = std::move(merged);
    result.payload = std::move(payload);
    return result;
  } catch (const std::exception& error) {
    result.error = std::string("FCStd import failed: ") + error.what();
    return result;
  } catch (...) {
    result.error = "Unknown failure while importing prepared FCStd geometry.";
    return result;
  }
}

}  // namespace brepsight
