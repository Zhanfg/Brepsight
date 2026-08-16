#include <jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

#include "mesh_document.h"
#include "stl_importer.h"

namespace {
constexpr const char* kTag = "CadEngine";
constexpr float kPi = 3.14159265358979323846f;

using brepsight::MeshData;
using brepsight::MeshVertex;
using brepsight::Vec3;

struct Mat4 {
  float m[16]{};
};

Mat4 identity() {
  Mat4 out{};
  out.m[0] = out.m[5] = out.m[10] = out.m[15] = 1.0f;
  return out;
}

Mat4 multiply(const Mat4& a, const Mat4& b) {
  Mat4 out{};
  for (int col = 0; col < 4; ++col) {
    for (int row = 0; row < 4; ++row) {
      float value = 0.0f;
      for (int k = 0; k < 4; ++k) {
        value += a.m[k * 4 + row] * b.m[col * 4 + k];
      }
      out.m[col * 4 + row] = value;
    }
  }
  return out;
}

Mat4 translation(float x, float y, float z) {
  Mat4 out = identity();
  out.m[12] = x;
  out.m[13] = y;
  out.m[14] = z;
  return out;
}

Mat4 rotationX(float radians) {
  Mat4 out = identity();
  const float c = std::cos(radians);
  const float s = std::sin(radians);
  out.m[5] = c;
  out.m[6] = s;
  out.m[9] = -s;
  out.m[10] = c;
  return out;
}

Mat4 rotationY(float radians) {
  Mat4 out = identity();
  const float c = std::cos(radians);
  const float s = std::sin(radians);
  out.m[0] = c;
  out.m[2] = -s;
  out.m[8] = s;
  out.m[10] = c;
  return out;
}

Mat4 perspective(float fovYRadians, float aspect, float nearPlane, float farPlane) {
  Mat4 out{};
  const float f = 1.0f / std::tan(fovYRadians * 0.5f);
  out.m[0] = f / aspect;
  out.m[5] = f;
  out.m[10] = (farPlane + nearPlane) / (nearPlane - farPlane);
  out.m[11] = -1.0f;
  out.m[14] = (2.0f * farPlane * nearPlane) / (nearPlane - farPlane);
  return out;
}

Mat4 orthographic(float left, float right, float bottom, float top, float nearPlane, float farPlane) {
  Mat4 out = identity();
  out.m[0] = 2.0f / (right - left);
  out.m[5] = 2.0f / (top - bottom);
  out.m[10] = -2.0f / (farPlane - nearPlane);
  out.m[12] = -(right + left) / (right - left);
  out.m[13] = -(top + bottom) / (top - bottom);
  out.m[14] = -(farPlane + nearPlane) / (farPlane - nearPlane);
  return out;
}

struct RenderState {
  std::mutex mutex;
  std::condition_variable wake;
  std::thread thread;
  ANativeWindow* window = nullptr;
  int width = 1;
  int height = 1;
  std::atomic<bool> stop{false};
  std::atomic<bool> dirty{true};
  float orbitX = 0.55f;
  float orbitY = -0.35f;
  float panX = 0.0f;
  float panY = 0.0f;
  float zoom = 1.0f;
  bool orthographic = false;
  int displayMode = 1;  // 0 shaded, 1 shaded+edges, 2 wireframe.
};

struct DocumentRecord {
  jlong handle = 0;
  std::string sourcePath;
  std::string formatId;
  bool committed = false;
  std::shared_ptr<MeshData> mesh;
};

RenderState g;
std::mutex gDocumentsMutex;
std::unordered_map<jlong, DocumentRecord> gDocuments;
std::atomic<jlong> gNextDocumentHandle{1};
jlong gCurrentDocumentHandle = 0;
std::atomic<uint64_t> gDocumentRevision{1};

std::mutex gLastErrorMutex;
std::string gLastError;

void setLastError(std::string message) {
  std::lock_guard lock(gLastErrorMutex);
  gLastError = std::move(message);
}

void markDirty() {
  g.dirty.store(true);
  g.wake.notify_all();
}

void destroyWindowLocked() {
  if (g.window != nullptr) {
    ANativeWindow_release(g.window);
    g.window = nullptr;
  }
}

std::shared_ptr<MeshData> currentMesh() {
  std::lock_guard lock(gDocumentsMutex);
  const auto it = gDocuments.find(gCurrentDocumentHandle);
  if (it == gDocuments.end()) return nullptr;
  return it->second.mesh;
}

GLuint compileShader(GLenum type, const char* source) {
  const GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, nullptr);
  glCompileShader(shader);
  GLint ok = GL_FALSE;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
  if (ok == GL_TRUE) return shader;

  GLint length = 0;
  glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
  std::string log(static_cast<std::size_t>(std::max(length, 1)), '\0');
  glGetShaderInfoLog(shader, length, nullptr, log.data());
  __android_log_print(ANDROID_LOG_ERROR, kTag, "Shader compile failed: %s", log.c_str());
  glDeleteShader(shader);
  return 0;
}

GLuint createProgram() {
  static constexpr const char* kVertexShader = R"GLSL(#version 300 es
layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec3 aBarycentric;
uniform mat4 uMvp;
uniform mat3 uNormalMatrix;
out vec3 vNormal;
out vec3 vBarycentric;
void main() {
  gl_Position = uMvp * vec4(aPosition, 1.0);
  vNormal = normalize(uNormalMatrix * aNormal);
  vBarycentric = aBarycentric;
}
)GLSL";

  static constexpr const char* kFragmentShader = R"GLSL(#version 300 es
precision highp float;
in vec3 vNormal;
in vec3 vBarycentric;
uniform int uDisplayMode;
uniform vec3 uBaseColor;
out vec4 fragColor;
void main() {
  vec3 lightDir = normalize(vec3(0.35, 0.55, 0.78));
  float diffuse = max(dot(normalize(vNormal), lightDir), 0.0);
  vec3 shaded = uBaseColor * (0.28 + 0.72 * diffuse);

  float nearestEdge = min(vBarycentric.x, min(vBarycentric.y, vBarycentric.z));
  float edgeWidth = max(fwidth(nearestEdge) * 1.25, 0.0005);
  float edge = 1.0 - smoothstep(0.0, edgeWidth, nearestEdge);
  vec3 edgeColor = vec3(0.055, 0.065, 0.075);

  if (uDisplayMode == 2) {
    if (edge < 0.12) discard;
    fragColor = vec4(edgeColor, 1.0);
  } else if (uDisplayMode == 1) {
    fragColor = vec4(mix(shaded, edgeColor, edge), 1.0);
  } else {
    fragColor = vec4(shaded, 1.0);
  }
}
)GLSL";

  const GLuint vs = compileShader(GL_VERTEX_SHADER, kVertexShader);
  const GLuint fs = compileShader(GL_FRAGMENT_SHADER, kFragmentShader);
  if (vs == 0 || fs == 0) {
    if (vs != 0) glDeleteShader(vs);
    if (fs != 0) glDeleteShader(fs);
    return 0;
  }

  const GLuint program = glCreateProgram();
  glAttachShader(program, vs);
  glAttachShader(program, fs);
  glLinkProgram(program);
  glDeleteShader(vs);
  glDeleteShader(fs);

  GLint ok = GL_FALSE;
  glGetProgramiv(program, GL_LINK_STATUS, &ok);
  if (ok == GL_TRUE) return program;

  GLint length = 0;
  glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);
  std::string log(static_cast<std::size_t>(std::max(length, 1)), '\0');
  glGetProgramInfoLog(program, length, nullptr, log.data());
  __android_log_print(ANDROID_LOG_ERROR, kTag, "Program link failed: %s", log.c_str());
  glDeleteProgram(program);
  return 0;
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

  if (!eglMakeCurrent(display, surface, surface, context)) {
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);
    return;
  }
  eglSwapInterval(display, 1);

  const GLuint program = createProgram();
  GLuint vao = 0;
  GLuint vbo = 0;
  glGenVertexArrays(1, &vao);
  glGenBuffers(1, &vbo);
  glBindVertexArray(vao);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(
      0, 3, GL_FLOAT, GL_FALSE, sizeof(MeshVertex),
      reinterpret_cast<const void*>(offsetof(MeshVertex, position)));
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(
      1, 3, GL_FLOAT, GL_FALSE, sizeof(MeshVertex),
      reinterpret_cast<const void*>(offsetof(MeshVertex, normal)));
  glEnableVertexAttribArray(2);
  glVertexAttribPointer(
      2, 3, GL_FLOAT, GL_FALSE, sizeof(MeshVertex),
      reinterpret_cast<const void*>(offsetof(MeshVertex, barycentric)));
  glBindVertexArray(0);

  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LEQUAL);
  glDisable(GL_CULL_FACE);

  uint64_t uploadedRevision = 0;
  std::shared_ptr<MeshData> uploadedMesh;
  GLsizei uploadedVertexCount = 0;

  while (!g.stop.load()) {
    int width = 1;
    int height = 1;
    float orbitX = 0.0f;
    float orbitY = 0.0f;
    float panX = 0.0f;
    float panY = 0.0f;
    float zoom = 1.0f;
    bool isOrthographic = false;
    int displayMode = 1;

    {
      std::unique_lock lock(g.mutex);
      g.wake.wait_for(lock, std::chrono::milliseconds(33), [] {
        return g.stop.load() || g.dirty.load();
      });
      width = std::max(g.width, 1);
      height = std::max(g.height, 1);
      orbitX = g.orbitX;
      orbitY = g.orbitY;
      panX = g.panX;
      panY = g.panY;
      zoom = g.zoom;
      isOrthographic = g.orthographic;
      displayMode = g.displayMode;
      g.dirty.store(false);
    }

    const uint64_t revision = gDocumentRevision.load();
    std::shared_ptr<MeshData> mesh = currentMesh();
    if (revision != uploadedRevision || mesh != uploadedMesh) {
      uploadedMesh = mesh;
      uploadedRevision = revision;
      uploadedVertexCount = 0;
      glBindBuffer(GL_ARRAY_BUFFER, vbo);
      if (mesh != nullptr && !mesh->vertices.empty()) {
        glBufferData(
            GL_ARRAY_BUFFER,
            static_cast<GLsizeiptr>(mesh->vertices.size() * sizeof(MeshVertex)),
            mesh->vertices.data(),
            GL_STATIC_DRAW);
        uploadedVertexCount = static_cast<GLsizei>(std::min<std::size_t>(
            mesh->vertices.size(), static_cast<std::size_t>(std::numeric_limits<GLsizei>::max())));
      } else {
        glBufferData(GL_ARRAY_BUFFER, 0, nullptr, GL_STATIC_DRAW);
      }
    }

    glViewport(0, 0, width, height);
    glClearColor(0.045f, 0.055f, 0.072f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (program != 0 && uploadedMesh != nullptr && uploadedVertexCount > 0 && uploadedMesh->bounds.valid) {
      const Vec3 center = uploadedMesh->bounds.center();
      const float extent = std::max(uploadedMesh->bounds.maxExtent(), 1.0e-3f);
      const float radius = extent * 0.6f;
      const float aspect = static_cast<float>(width) / static_cast<float>(height);
      const float safeZoom = std::clamp(zoom, 0.05f, 20.0f);

      const Mat4 centerModel = translation(-center.x, -center.y, -center.z);
      const Mat4 rotation = multiply(rotationY(orbitX), rotationX(orbitY));
      const Mat4 model = multiply(rotation, centerModel);

      Mat4 projection{};
      Mat4 view{};
      if (isOrthographic) {
        const float halfHeight = std::max(radius * 1.35f / safeZoom, 1.0e-3f);
        const float halfWidth = halfHeight * aspect;
        projection = orthographic(-halfWidth, halfWidth, -halfHeight, halfHeight, -radius * 20.0f, radius * 20.0f);
        view = translation(panX * extent * 2.0f, -panY * extent * 2.0f, 0.0f);
      } else {
        const float distance = std::max(radius * 3.2f / safeZoom, radius * 1.05f);
        const float nearPlane = std::max(radius * 0.01f, 1.0e-4f);
        const float farPlane = std::max(distance + radius * 20.0f, nearPlane + 1.0f);
        projection = perspective(45.0f * kPi / 180.0f, aspect, nearPlane, farPlane);
        view = translation(panX * extent * 2.0f, -panY * extent * 2.0f, -distance);
      }

      const Mat4 mvp = multiply(projection, multiply(view, model));
      const float normalMatrix[9] = {
          rotation.m[0], rotation.m[1], rotation.m[2],
          rotation.m[4], rotation.m[5], rotation.m[6],
          rotation.m[8], rotation.m[9], rotation.m[10],
      };

      glUseProgram(program);
      glUniformMatrix4fv(glGetUniformLocation(program, "uMvp"), 1, GL_FALSE, mvp.m);
      glUniformMatrix3fv(glGetUniformLocation(program, "uNormalMatrix"), 1, GL_FALSE, normalMatrix);
      glUniform1i(glGetUniformLocation(program, "uDisplayMode"), displayMode);
      glUniform3f(glGetUniformLocation(program, "uBaseColor"), 0.70f, 0.76f, 0.84f);
      glBindVertexArray(vao);
      glDrawArrays(GL_TRIANGLES, 0, uploadedVertexCount);
      glBindVertexArray(0);
      glUseProgram(0);
    }

    eglSwapBuffers(display, surface);
  }

  if (vbo != 0) glDeleteBuffers(1, &vbo);
  if (vao != 0) glDeleteVertexArrays(1, &vao);
  if (program != 0) glDeleteProgram(program);

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

std::string lowercaseExtension(const std::string& path) {
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
  return handle;
}

extern "C" JNIEXPORT jlong JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeCommitDocumentTransaction(
    JNIEnv*, jobject, jlong handle) {
  {
    std::lock_guard lock(gDocumentsMutex);
    auto it = gDocuments.find(handle);
    if (it == gDocuments.end()) return -1;
    const jlong previous = gCurrentDocumentHandle;
    it->second.committed = true;
    gCurrentDocumentHandle = handle;
    gDocumentRevision.fetch_add(1);
    markDirty();
    return previous;
  }
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

extern "C" JNIEXPORT jlong JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeDocumentTriangleCount(
    JNIEnv*, jobject, jlong handle) {
  std::lock_guard lock(gDocumentsMutex);
  const DocumentRecord* record = findDocumentLocked(handle);
  if (record == nullptr || record->mesh == nullptr) return 0;
  return static_cast<jlong>(record->mesh->triangleCount);
}

extern "C" JNIEXPORT jstring JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeLastError(
    JNIEnv* env, jobject) {
  std::lock_guard lock(gLastErrorMutex);
  return toJString(env, gLastError);
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeLoadModel(
    JNIEnv* env, jobject, jstring path) {
  const std::string modelPath = toString(env, path);
  const std::string extension = lowercaseExtension(modelPath);
  if (extension != "stl") {
    setLastError("This native provider currently opens STL. Other registered formats are being connected incrementally.");
    return 1002;
  }

  auto mesh = std::make_shared<MeshData>();
  std::string error;
  if (!brepsight::loadStl(modelPath, *mesh, error)) {
    setLastError(error.empty() ? "Unable to parse STL file." : error);
    return 1101;
  }

  const jlong handle = gNextDocumentHandle.fetch_add(1);
  DocumentRecord record;
  record.handle = handle;
  record.sourcePath = modelPath;
  record.formatId = "stl";
  record.committed = true;
  record.mesh = std::move(mesh);

  {
    std::lock_guard lock(gDocumentsMutex);
    const jlong previous = gCurrentDocumentHandle;
    gDocuments.emplace(handle, std::move(record));
    gCurrentDocumentHandle = handle;
    if (previous != 0 && previous != handle) gDocuments.erase(previous);
  }

  {
    std::lock_guard lock(g.mutex);
    g.panX = 0.0f;
    g.panY = 0.0f;
    g.zoom = 1.0f;
  }
  gDocumentRevision.fetch_add(1);
  setLastError({});
  markDirty();
  __android_log_print(ANDROID_LOG_INFO, kTag, "Loaded STL: %s", modelPath.c_str());
  return 0;
}

extern "C" JNIEXPORT void JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeCommand(
    JNIEnv* env, jobject, jstring command, jdouble a, jdouble b) {
  const std::string cmd = toString(env, command);
  {
    std::lock_guard lock(g.mutex);
    if (cmd == "orbit") {
      g.orbitX += static_cast<float>(a) * 0.010f;
      g.orbitY += static_cast<float>(b) * 0.010f;
      g.orbitY = std::clamp(g.orbitY, -1.55f, 1.55f);
    } else if (cmd == "pan") {
      g.panX += static_cast<float>(a) / static_cast<float>(std::max(g.width, 1));
      g.panY += static_cast<float>(b) / static_cast<float>(std::max(g.height, 1));
    } else if (cmd == "zoom") {
      if (a > 0.01) g.zoom = std::clamp(g.zoom * static_cast<float>(a), 0.05f, 20.0f);
    } else if (cmd == "fit_all") {
      g.panX = 0.0f;
      g.panY = 0.0f;
      g.zoom = 1.0f;
    } else if (cmd == "orthographic") {
      g.orthographic = true;
    } else if (cmd == "perspective") {
      g.orthographic = false;
    } else if (cmd == "shaded") {
      g.displayMode = 0;
    } else if (cmd == "shaded_edges") {
      g.displayMode = 1;
    } else if (cmd == "wireframe") {
      g.displayMode = 2;
    }
    g.dirty.store(true);
  }
  g.wake.notify_all();
}
