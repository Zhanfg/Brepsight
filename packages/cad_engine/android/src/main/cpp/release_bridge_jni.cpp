#include <jni.h>

extern "C" JNIEXPORT jboolean JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeSetSectionPlane(
    JNIEnv*, jobject, jboolean, jdouble, jdouble, jdouble, jdouble);
extern "C" JNIEXPORT jstring JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeSectionPlaneError(
    JNIEnv*, jobject);
extern "C" JNIEXPORT void JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeInvalidatePickCache(
    JNIEnv*, jobject);
extern "C" JNIEXPORT jdoubleArray JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativePickModelPoint(
    JNIEnv*, jobject, jstring, jint, jint, jdouble, jdouble, jdouble, jdouble,
    jdouble, jboolean, jdouble, jdouble);
extern "C" JNIEXPORT jint JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeExportCurrentModel(
    JNIEnv*, jobject, jstring, jstring);

extern "C" JNIEXPORT jboolean JNICALL
Java_dev_brepsight_cad_1engine_CadEngineEntrypoint_nativeSetSectionPlane(
    JNIEnv* env,
    jobject self,
    jboolean enabled,
    jdouble nx,
    jdouble ny,
    jdouble nz,
    jdouble offset) {
  return Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeSetSectionPlane(
      env, self, enabled, nx, ny, nz, offset);
}

extern "C" JNIEXPORT jstring JNICALL
Java_dev_brepsight_cad_1engine_CadEngineEntrypoint_nativeSectionPlaneError(
    JNIEnv* env, jobject self) {
  return Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeSectionPlaneError(env, self);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_brepsight_cad_1engine_CadEngineEntrypoint_nativeInvalidatePickCache(
    JNIEnv* env, jobject self) {
  Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeInvalidatePickCache(env, self);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_dev_brepsight_cad_1engine_CadEngineEntrypoint_nativePickModelPoint(
    JNIEnv* env,
    jobject self,
    jstring path,
    jint width,
    jint height,
    jdouble orbitX,
    jdouble orbitY,
    jdouble panX,
    jdouble panY,
    jdouble zoom,
    jboolean orthographic,
    jdouble screenX,
    jdouble screenY) {
  return Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativePickModelPoint(
      env,
      self,
      path,
      width,
      height,
      orbitX,
      orbitY,
      panX,
      panY,
      zoom,
      orthographic,
      screenX,
      screenY);
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_brepsight_cad_1engine_CadEngineEntrypoint_nativeExportCurrentMesh(
    JNIEnv* env,
    jobject self,
    jstring path,
    jstring formatId) {
  return Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeExportCurrentModel(
      env, self, path, formatId);
}
