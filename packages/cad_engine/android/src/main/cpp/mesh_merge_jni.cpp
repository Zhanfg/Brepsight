#include <jni.h>

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

#include "mesh_merge.h"
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

std::string extensionOf(const std::string& path) {
  const auto slash = path.find_last_of("/\\");
  const auto dot = path.find_last_of('.');
  if (dot == std::string::npos || (slash != std::string::npos && dot < slash)) return {};
  std::string ext = path.substr(dot + 1);
  std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return ext;
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeMergeModelFiles(
    JNIEnv* env,
    jobject,
    jobjectArray paths,
    jstring outputPathValue,
    jstring outputFormatValue) {
  if (paths == nullptr) return -1;
  const jsize count = env->GetArrayLength(paths);
  if (count < 2) return -2;

  std::vector<brepsight::MeshData> meshes;
  meshes.reserve(static_cast<std::size_t>(count));

  for (jsize i = 0; i < count; ++i) {
    auto* raw = static_cast<jstring>(env->GetObjectArrayElement(paths, i));
    if (raw == nullptr) return -3;
    const std::string path = toString(env, raw);
    env->DeleteLocalRef(raw);

    brepsight::MeshData mesh;
    std::string error;
    bool loaded = false;
    const std::string extension = extensionOf(path);
    if (extension == "stl") {
      loaded = brepsight::loadStl(path, mesh, error);
    } else if (extension == "obj") {
      loaded = brepsight::loadObj(path, mesh, error);
    } else {
      return -4;
    }
    if (!loaded) return -5;
    meshes.push_back(std::move(mesh));
  }

  brepsight::MeshData merged = brepsight::mergeMeshes(meshes);
  if (merged.triangleCount == 0 || merged.vertices.empty()) return -6;

  const std::string outputPath = toString(env, outputPathValue);
  std::string outputFormat = toString(env, outputFormatValue);
  std::transform(outputFormat.begin(), outputFormat.end(), outputFormat.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });

  std::string error;
  bool written = false;
  if (outputFormat == "obj") {
    written = brepsight::writeObj(outputPath, merged, error);
  } else if (outputFormat == "stl") {
    written = brepsight::writeBinaryStl(outputPath, merged, error);
  } else {
    return -7;
  }
  return written ? count : -8;
}
