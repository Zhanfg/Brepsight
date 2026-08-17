#include <jni.h>

#include <string>

#include "mesh_transform.h"
#include "mesh_writer.h"
#include "obj_importer.h"

namespace {

std::string toString(JNIEnv* env, jstring value) {
  if (value == nullptr) return {};
  const char* chars = env->GetStringUTFChars(value, nullptr);
  std::string out = chars == nullptr ? std::string{} : std::string(chars);
  if (chars != nullptr) env->ReleaseStringUTFChars(value, chars);
  return out;
}

jstring errorString(JNIEnv* env, const std::string& message) {
  return env->NewStringUTF(message.c_str());
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_dev_brepsight_cad_1engine_CadEngineEntrypoint_nativeTransformObjFile(
    JNIEnv* env,
    jobject,
    jstring inputPath,
    jstring outputPath,
    jdouble tx,
    jdouble ty,
    jdouble tz,
    jdouble rx,
    jdouble ry,
    jdouble rz,
    jdouble sx,
    jdouble sy,
    jdouble sz) {
  const std::string input = toString(env, inputPath);
  const std::string output = toString(env, outputPath);
  if (input.empty() || output.empty()) {
    return errorString(env, "Mesh edit input/output path is empty.");
  }

  brepsight::MeshData mesh;
  std::string error;
  if (!brepsight::loadObj(input, mesh, error)) {
    return errorString(env, error.empty() ? "Unable to read mesh edit snapshot." : error);
  }

  brepsight::MeshTransform transform;
  transform.translation = {
      static_cast<float>(tx), static_cast<float>(ty), static_cast<float>(tz)};
  transform.rotationDegrees = {
      static_cast<float>(rx), static_cast<float>(ry), static_cast<float>(rz)};
  transform.scale = {
      static_cast<float>(sx), static_cast<float>(sy), static_cast<float>(sz)};
  if (!brepsight::applyMeshTransform(mesh, transform, error)) {
    return errorString(env, error.empty() ? "Unable to transform mesh edit snapshot." : error);
  }
  if (!brepsight::writeObj(output, mesh, error)) {
    return errorString(env, error.empty() ? "Unable to write mesh edit snapshot." : error);
  }
  return nullptr;
}
