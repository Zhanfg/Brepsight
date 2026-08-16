#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <android/log.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace {
constexpr const char* kTag = "CadEngine";

struct RenderState {
  std::mutex mutex;
  std::condition_variable wake;
  std::thread thread;
  ANativeWindow* window = nullptr;
  int width = 1;
  int height = 1;
  std::atomic<bool> stop{false};
  std::atomic<bool> dirty{true};
  double orbitX = 0.0;
  double orbitY = 0.0;
  double zoom = 1.0;
};

struct DocumentRecord {
  jlong handle = 0;
  std::string sourcePath;
  std::string formatId;
  bool committed = false;
};

RenderState g;
std::mutex gDocumentsMutex;
std::unordered_map<jlong, DocumentRecord> gDocuments;
std::atomic<jlong> gNextDocumentHandle{1};
jlong gCurrentDocumentHandle = 0;

void destroyWindowLocked() {
  if (g.window != nullptr) {
    ANativeWindow_release(g.window);
    g.window = nullptr;
  }
}

void renderLoop() {
  EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr)) {
    __android_log_print(ANDROID_LOG_ERROR, kTag, "eglInitialize failed");
    return;
  }

  const EGLint configAttrs[] = {
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
      EGL_DEPTH_SIZE, 24,
      EGL_NONE
  };
  EGLConfig config = nullptr;
  EGLint configCount = 0;
  if (!eglChooseConfig(display, configAttrs, &config, 1, &configCount) || configCount < 1) {
    __android_log_print(ANDROID_LOG_ERROR, kTag, "eglChooseConfig failed");
    eglTerminate(display);
    return;
  }
  const EGLint contextAttrs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttrs);
  if (context == EGL_NO_CONTEXT) {
    __android_log_print(ANDROID_LOG_ERROR, kTag, "eglCreateContext failed");
    eglTerminate(display);
    return;
  }

  ANativeWindow* localWindow = nullptr;
  {
    std::lock_guard lock(g.mutex);
    if (g.window != nullptr) {
      ANativeWindow_acquire(g.window);
      localWindow = g.window;
    }
  }
  if (localWindow == nullptr) {
    eglDestroyContext(display, context);
    eglTerminate(display);
    return;
  }

  EGLSurface surface = eglCreateWindowSurface(display, config, localWindow, nullptr);
  ANativeWindow_release(localWindow);
  if (surface == EGL_NO_SURFACE) {
    __android_log_print(ANDROID_LOG_ERROR, kTag, "eglCreateWindowSurface failed");
    eglDestroyContext(display, context);
    eglTerminate(display);
    return;
  }
  eglMakeCurrent(display, surface, surface, context);
  eglSwapInterval(display, 1);

  while (!g.stop.load()) {
    int width;
    int height;
    double orbitX;
    double orbitY;
    double zoom;
    {
      std::unique_lock lock(g.mutex);
      g.wake.wait_for(lock, std::chrono::milliseconds(16), [] {
        return g.stop.load() || g.dirty.load();
      });
      width = g.width;
      height = g.height;
      orbitX = g.orbitX;
      orbitY = g.orbitY;
      zoom = g.zoom;
      g.dirty.store(false);
    }

    glViewport(0, 0, width, height);
    // Proof renderer only: subtle state-dependent clear color verifies that
    // gestures reach native code without involving Qt/QML.
    const float r = 0.055f + static_cast<float>(std::fmod(std::abs(orbitX) * 0.0007, 0.025));
    const float gch = 0.070f + static_cast<float>(std::fmod(std::abs(orbitY) * 0.0007, 0.025));
    const float b = 0.095f + static_cast<float>(std::fmod(std::abs(zoom - 1.0) * 0.04, 0.035));
    glClearColor(r, gch, b, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    eglSwapBuffers(display, surface);
  }

  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  eglDestroySurface(display, surface);
  eglDestroyContext(display, context);
  eglTerminate(display);
}

void stopRenderer() {
  g.stop.store(true);
  g.wake.notify_all();
  if (g.thread.joinable()) g.thread.join();
  std::lock_guard lock(g.mutex);
  destroyWindowLocked();
  g.stop.store(false);
}

std::string toString(JNIEnv* env, jstring value) {
  if (value == nullptr) return {};
  const char* chars = env->GetStringUTFChars(value, nullptr);
  std::string out = chars ? chars : "";
  if (chars) env->ReleaseStringUTFChars(value, chars);
  return out;
}

jstring toJString(JNIEnv* env, const std::string& value) {
  return env->NewStringUTF(value.c_str());
}

const DocumentRecord* findDocumentLocked(jlong handle) {
  const auto it = gDocuments.find(handle);
  return it == gDocuments.end() ? nullptr : &it->second;
}
}  // namespace

extern "C" JNIEXPORT void JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeAttachSurface(
    JNIEnv* env, jobject, jobject surface, jint width, jint height) {
  stopRenderer();
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) return;
  {
    std::lock_guard lock(g.mutex);
    g.window = window;
    g.width = width > 0 ? width : 1;
    g.height = height > 0 ? height : 1;
    g.dirty.store(true);
  }
  g.thread = std::thread(renderLoop);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeDetachSurface(
    JNIEnv*, jobject) {
  stopRenderer();
}

extern "C" JNIEXPORT void JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeResize(
    JNIEnv*, jobject, jint width, jint height) {
  std::lock_guard lock(g.mutex);
  g.width = width > 0 ? width : 1;
  g.height = height > 0 ? height : 1;
  g.dirty.store(true);
  g.wake.notify_all();
}

extern "C" JNIEXPORT jlong JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeBeginDocumentTransaction(
    JNIEnv* env, jobject, jstring path, jstring formatId) {
  const jlong handle = gNextDocumentHandle.fetch_add(1);
  DocumentRecord record;
  record.handle = handle;
  record.sourcePath = toString(env, path);
  record.formatId = toString(env, formatId);
  record.committed = false;

  {
    std::lock_guard lock(gDocumentsMutex);
    gDocuments.emplace(handle, std::move(record));
  }

  __android_log_print(
      ANDROID_LOG_INFO,
      kTag,
      "Begin document transaction handle=%lld",
      static_cast<long long>(handle));
  return handle;
}

extern "C" JNIEXPORT jlong JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeCommitDocumentTransaction(
    JNIEnv*, jobject, jlong handle) {
  std::lock_guard lock(gDocumentsMutex);
  auto it = gDocuments.find(handle);
  if (it == gDocuments.end()) return -1;

  const jlong previous = gCurrentDocumentHandle;
  it->second.committed = true;
  gCurrentDocumentHandle = handle;
  return previous;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeDiscardDocumentTransaction(
    JNIEnv*, jobject, jlong handle) {
  std::lock_guard lock(gDocumentsMutex);
  if (handle == gCurrentDocumentHandle) return JNI_FALSE;
  return gDocuments.erase(handle) > 0 ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeCurrentDocumentHandle(
    JNIEnv*, jobject) {
  std::lock_guard lock(gDocumentsMutex);
  return gCurrentDocumentHandle;
}

extern "C" JNIEXPORT jstring JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeDocumentSourcePath(
    JNIEnv* env, jobject, jlong handle) {
  std::lock_guard lock(gDocumentsMutex);
  const DocumentRecord* record = findDocumentLocked(handle);
  return record == nullptr ? nullptr : toJString(env, record->sourcePath);
}

extern "C" JNIEXPORT jstring JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeDocumentFormatId(
    JNIEnv* env, jobject, jlong handle) {
  std::lock_guard lock(gDocumentsMutex);
  const DocumentRecord* record = findDocumentLocked(handle);
  return record == nullptr ? nullptr : toJString(env, record->formatId);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeDocumentCommitted(
    JNIEnv*, jobject, jlong handle) {
  std::lock_guard lock(gDocumentsMutex);
  const DocumentRecord* record = findDocumentLocked(handle);
  return record != nullptr && record->committed ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeLoadModel(
    JNIEnv* env, jobject, jstring path) {
  const std::string modelPath = toString(env, path);
  __android_log_print(ANDROID_LOG_INFO, kTag, "Requested model: %s", modelPath.c_str());
  // 1001 = native Surface path works, OCCT importer not linked in Stage 1.
  return 1001;
}

extern "C" JNIEXPORT void JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeCommand(
    JNIEnv* env, jobject, jstring command, jdouble a, jdouble b) {
  const std::string cmd = toString(env, command);
  {
    std::lock_guard lock(g.mutex);
    if (cmd == "orbit") {
      g.orbitX += a;
      g.orbitY += b;
    } else if (cmd == "pan") {
      g.orbitX += a * 0.25;
      g.orbitY += b * 0.25;
    } else if (cmd == "zoom") {
      if (a > 0.01) g.zoom *= a;
    }
    g.dirty.store(true);
  }
  g.wake.notify_all();
}
