#include "freecad_fcstd_importer.h"

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <fstream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "brep_occt_importer.h"

namespace brepsight {
namespace {

constexpr const char* kManifestHeader = "BREPSIGHT_FCSTD_V1";
constexpr std::size_t kMaxManifestBytes = 16 * 1024 * 1024;
constexpr std::size_t kMaxShapeRecords = 10000;
constexpr std::size_t kMaxDocumentObjects = 1000000;

struct ShapeRecord {
  std::string objectName;
  std::string extractedPath;
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

void appendMesh(const MeshData& source, MeshData& destination) {
  if (source.vertices.size() > destination.vertices.max_size() - destination.vertices.size()) {
    throw std::runtime_error("FCStd display mesh exceeds addressable vertex capacity.");
  }
  destination.vertices.insert(destination.vertices.end(), source.vertices.begin(), source.vertices.end());
  for (const MeshVertex& vertex : source.vertices) {
    destination.bounds.include(vertex.position);
  }
  if (source.triangleCount > std::numeric_limits<std::size_t>::max() - destination.triangleCount) {
    throw std::runtime_error("FCStd triangle-count overflow.");
  }
  destination.triangleCount += source.triangleCount;
  destination.hasNormals = destination.hasNormals || source.hasNormals;
  destination.hasUv = destination.hasUv || source.hasUv;
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
    std::vector<ShapeRecord> shapeRecords;
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

      if (fields[0] == "shape") {
        if (fields.size() != 3 || shapeRecords.size() >= kMaxShapeRecords) {
          result.error = "Prepared FCStd shape record is invalid or exceeds the safety limit.";
          return result;
        }
        ShapeRecord record;
        if (!percentDecode(fields[1], record.objectName) ||
            !percentDecode(fields[2], record.extractedPath) ||
            record.objectName.empty() || record.extractedPath.empty()) {
          result.error = "Prepared FCStd shape record encoding is invalid.";
          return result;
        }
        shapeRecords.push_back(std::move(record));
        continue;
      }

      result.error = "Prepared FCStd manifest contains an unknown record type.";
      return result;
    }

    if (originalSource.empty() || !objectCountSeen || shapeRecords.empty()) {
      result.error = "Prepared FCStd manifest is incomplete.";
      return result;
    }

    auto payload = std::make_shared<FcStdPayload>();
    payload->originalSourcePath = originalSource;
    payload->documentObjectCount = documentObjectCount;

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
      appendMesh(*imported.displayMesh, *merged);
      payload->shapes.push_back(FcStdShapePayload{record.objectName, std::move(imported.exactPayload)});
    }

    if (payload->shapes.empty() || merged->vertices.empty()) {
      result.error = firstFailure.empty()
          ? "FCStd contained no readable saved BREP geometry."
          : "FCStd saved geometry could not be read: " + firstFailure;
      return result;
    }

    result.sourcePathOverride = originalSource;
    result.rootObjectCount = payload->shapes.size();
    result.hierarchyNodeCount = std::max(documentObjectCount, payload->shapes.size());
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
