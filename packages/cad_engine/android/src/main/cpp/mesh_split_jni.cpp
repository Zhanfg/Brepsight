#include <jni.h>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <iomanip>
#include <sstream>
#include <string>

#include "mesh_components.h"
#include "mesh_writer.h"
#include "obj_importer.h"
#include "stl_importer.h"

namespace {

std::string toString(JNIEnv* env, jstring value) {
  if (value == nullptr) return {};
  const char* chars = env->GetStringUTFChars(value, nullptr);
  std::string out = chars ? chars : "";
  if (chars != nullptr) env->ReleaseStringUTFChars(value, chars);
  return out;
}

std::string lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return value;
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeSplitModelFile(
    JNIEnv* env,
    jobject,
    jstring path,
    jstring sourceFormatId,
    jstring outputDirectory,
    jstring outputFormatId) {
  const std::string modelPath = toString(env, path);
  const std::string sourceFormat = lower(toString(env, sourceFormatId));
  const std::string outputFormat = lower(toString(env, outputFormatId));
  const std::filesystem::path outputDir(toString(env, outputDirectory));

  brepsight::MeshData mesh;
  std::string error;
  bool loaded = false;
  if (sourceFormat == "stl") {
    loaded = brepsight::loadStl(modelPath, mesh, error);
  } else if (sourceFormat == "obj") {
    loaded = brepsight::loadObj(modelPath, mesh, error);
  } else {
    return -2;
  }
  if (!loaded) return -3;
  if (outputFormat != "stl" && outputFormat != "obj") return -4;

  const std::vector<brepsight::MeshData> components = brepsight::splitConnectedComponents(mesh);
  if (components.empty()) return 0;

  std::error_code filesystemError;
  std::filesystem::create_directories(outputDir, filesystemError);
  if (filesystemError) return -5;

  for (std::size_t i = 0; i < components.size(); ++i) {
    std::ostringstream filename;
    filename << "part_" << std::setw(3) << std::setfill('0') << (i + 1) << '.' << outputFormat;
    const std::filesystem::path outputPath = outputDir / filename.str();
    error.clear();
    bool written = false;
    if (outputFormat == "stl") {
      written = brepsight::writeBinaryStl(outputPath.string(), components[i], error);
    } else {
      written = brepsight::writeObj(outputPath.string(), components[i], error);
    }
    if (!written) return -6;
  }

  return static_cast<jint>(components.size());
}
