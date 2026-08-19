#include <jni.h>

#include <mutex>
#include <string>

#include "section_filter.h"

namespace {
std::mutex gSectionErrorMutex;
std::string gSectionError;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeSetSectionPlane(
    JNIEnv*, jobject, jboolean enabled, jdouble nx, jdouble ny, jdouble nz, jdouble offset) {
  std::string error;
  const bool ok = brepsight::setActiveSectionPlane(
      enabled == JNI_TRUE,
      brepsight::Vec3{
          static_cast<float>(nx),
          static_cast<float>(ny),
          static_cast<float>(nz)},
      static_cast<float>(offset),
      error);
  std::lock_guard lock(gSectionErrorMutex);
  gSectionError = std::move(error);
  return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeSectionPlaneError(
    JNIEnv* env, jobject) {
  std::lock_guard lock(gSectionErrorMutex);
  return env->NewStringUTF(gSectionError.c_str());
}
