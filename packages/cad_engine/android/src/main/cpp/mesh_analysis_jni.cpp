#include <jni.h>

#include <algorithm>
#include <cctype>
#include <locale>
#include <sstream>
#include <string>

#include "mesh_analysis.h"
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

std::string analysisJson(const brepsight::MeshAnalysis& analysis) {
  const auto& min = analysis.bounds.min;
  const auto& max = analysis.bounds.max;
  const double sizeX = analysis.bounds.valid ? static_cast<double>(max.x - min.x) : 0.0;
  const double sizeY = analysis.bounds.valid ? static_cast<double>(max.y - min.y) : 0.0;
  const double sizeZ = analysis.bounds.valid ? static_cast<double>(max.z - min.z) : 0.0;

  std::ostringstream out;
  out.imbue(std::locale::classic());
  out.precision(12);
  out << '{'
      << "\"triangleCount\":" << analysis.triangleCount << ','
      << "\"uniqueVertexCount\":" << analysis.uniqueVertexCount << ','
      << "\"openEdgeCount\":" << analysis.openEdgeCount << ','
      << "\"nonManifoldEdgeCount\":" << analysis.nonManifoldEdgeCount << ','
      << "\"connectedComponentCount\":" << analysis.connectedComponentCount << ','
      << "\"degenerateTriangleCount\":" << analysis.degenerateTriangleCount << ','
      << "\"surfaceArea\":" << analysis.surfaceArea << ','
      << "\"enclosedVolume\":" << analysis.enclosedVolume << ','
      << "\"closed\":" << (analysis.closed ? "true" : "false") << ','
      << "\"unitKnown\":false,"
      << "\"unitLabel\":\"model-unit\","
      << "\"boundsMin\":[" << min.x << ',' << min.y << ',' << min.z << "],"
      << "\"boundsMax\":[" << max.x << ',' << max.y << ',' << max.z << "],"
      << "\"size\":[" << sizeX << ',' << sizeY << ',' << sizeZ << ']'
      << '}';
  return out.str();
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeAnalyzeModelFile(
    JNIEnv* env, jobject, jstring path, jstring formatId) {
  const std::string modelPath = toString(env, path);
  const std::string format = lower(toString(env, formatId));

  brepsight::MeshData mesh;
  std::string error;
  bool loaded = false;
  if (format == "stl") {
    loaded = brepsight::loadStl(modelPath, mesh, error);
  } else if (format == "obj") {
    loaded = brepsight::loadObj(modelPath, mesh, error);
  }

  if (!loaded) {
    return env->NewStringUTF("");
  }

  const brepsight::MeshAnalysis analysis = brepsight::analyzeMesh(mesh);
  const std::string json = analysisJson(analysis);
  return env->NewStringUTF(json.c_str());
}
