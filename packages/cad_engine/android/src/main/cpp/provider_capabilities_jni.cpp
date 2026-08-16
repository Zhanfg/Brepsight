#include <jni.h>

extern "C" JNIEXPORT jboolean JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeOcctProviderEnabled(
    JNIEnv*, jobject) {
#if defined(BREPSIGHT_WITH_OCCT)
  return JNI_TRUE;
#else
  return JNI_FALSE;
#endif
}
