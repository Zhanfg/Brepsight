#include <jni.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <memory>
#include <mutex>
#include <string>

#include "mesh_document.h"
#include "runtime_model_loader.h"

namespace {

using brepsight::MeshData;
using brepsight::MeshVertex;
using brepsight::Vec3;

constexpr float kPi = 3.14159265358979323846f;
constexpr float kHitEpsilon = 1.0e-5f;
constexpr float kSnapRadiusPixels = 18.0f;
constexpr int kSnapFree = 0;
constexpr int kSnapVertex = 1;
constexpr int kSnapEdgeMidpoint = 2;
constexpr int kSnapFaceCenter = 3;

struct Mat4 { float m[16]{}; };
struct ClipPoint { float x = 0; float y = 0; float z = 0; float w = 1; };

std::mutex gPickCacheMutex;
std::string gPickCachePath;
std::shared_ptr<MeshData> gPickCacheMesh;

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
      for (int k = 0; k < 4; ++k) value += a.m[k * 4 + row] * b.m[col * 4 + k];
      out.m[col * 4 + row] = value;
    }
  }
  return out;
}

Mat4 translation(float x, float y, float z) {
  Mat4 out = identity();
  out.m[12] = x; out.m[13] = y; out.m[14] = z;
  return out;
}

Mat4 rotationX(float radians) {
  Mat4 out = identity();
  const float c = std::cos(radians); const float s = std::sin(radians);
  out.m[5] = c; out.m[6] = s; out.m[9] = -s; out.m[10] = c;
  return out;
}

Mat4 rotationY(float radians) {
  Mat4 out = identity();
  const float c = std::cos(radians); const float s = std::sin(radians);
  out.m[0] = c; out.m[2] = -s; out.m[8] = s; out.m[10] = c;
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

ClipPoint transform(const Mat4& m, const Vec3& p) {
  return {
      m.m[0] * p.x + m.m[4] * p.y + m.m[8] * p.z + m.m[12],
      m.m[1] * p.x + m.m[5] * p.y + m.m[9] * p.z + m.m[13],
      m.m[2] * p.x + m.m[6] * p.y + m.m[10] * p.z + m.m[14],
      m.m[3] * p.x + m.m[7] * p.y + m.m[11] * p.z + m.m[15],
  };
}

struct ScreenPoint {
  float x = 0; float y = 0; float z = 0; float reciprocalW = 1;
};

bool toScreen(const ClipPoint& clip, int width, int height, ScreenPoint& out) {
  if (!std::isfinite(clip.w) || std::abs(clip.w) <= 1.0e-8f) return false;
  const float invW = 1.0f / clip.w;
  const float nx = clip.x * invW;
  const float ny = clip.y * invW;
  const float nz = clip.z * invW;
  if (!std::isfinite(nx) || !std::isfinite(ny) || !std::isfinite(nz)) return false;
  out.x = (nx * 0.5f + 0.5f) * static_cast<float>(width);
  out.y = (1.0f - (ny * 0.5f + 0.5f)) * static_cast<float>(height);
  out.z = nz;
  out.reciprocalW = invW;
  return true;
}

float edge(float ax, float ay, float bx, float by, float px, float py) {
  return (px - ax) * (by - ay) - (py - ay) * (bx - ax);
}

bool barycentric2d(
    const ScreenPoint& a,
    const ScreenPoint& b,
    const ScreenPoint& c,
    float px,
    float py,
    std::array<float, 3>& weights) {
  const float area = edge(a.x, a.y, b.x, b.y, c.x, c.y);
  if (!std::isfinite(area) || std::abs(area) <= 1.0e-8f) return false;
  weights[0] = edge(b.x, b.y, c.x, c.y, px, py) / area;
  weights[1] = edge(c.x, c.y, a.x, a.y, px, py) / area;
  weights[2] = 1.0f - weights[0] - weights[1];
  return weights[0] >= -kHitEpsilon && weights[1] >= -kHitEpsilon && weights[2] >= -kHitEpsilon;
}

std::shared_ptr<MeshData> meshForPath(const std::string& path) {
  std::lock_guard lock(gPickCacheMutex);
  if (gPickCacheMesh != nullptr && gPickCachePath == path) return gPickCacheMesh;
  auto loaded = brepsight::loadRuntimeModel(path);
  if (!loaded.ok()) {
    gPickCachePath.clear();
    gPickCacheMesh.reset();
    return nullptr;
  }
  gPickCachePath = path;
  gPickCacheMesh = std::move(loaded.mesh);
  return gPickCacheMesh;
}

bool vertexVisible(const MeshData& mesh, std::size_t vertexIndex) {
  if (mesh.drawRanges.empty()) return true;
  for (const auto& range : mesh.drawRanges) {
    if (!range.visible) continue;
    if (vertexIndex >= range.firstVertex && vertexIndex < range.firstVertex + range.vertexCount) return true;
  }
  return false;
}

std::string toString(JNIEnv* env, jstring value) {
  if (value == nullptr) return {};
  const char* chars = env->GetStringUTFChars(value, nullptr);
  std::string out = chars ? chars : "";
  if (chars != nullptr) env->ReleaseStringUTFChars(value, chars);
  return out;
}

Vec3 midpoint(const Vec3& a, const Vec3& b) {
  return {(a.x + b.x) * 0.5f, (a.y + b.y) * 0.5f, (a.z + b.z) * 0.5f};
}

Vec3 centroid(const Vec3& a, const Vec3& b, const Vec3& c) {
  return {(a.x + b.x + c.x) / 3.0f,
          (a.y + b.y + c.y) / 3.0f,
          (a.z + b.z + c.z) / 3.0f};
}

}  // namespace

extern "C" JNIEXPORT void JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativeInvalidatePickCache(
    JNIEnv*, jobject) {
  std::lock_guard lock(gPickCacheMutex);
  gPickCachePath.clear();
  gPickCacheMesh.reset();
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_dev_brepsight_cad_1engine_CadEnginePlugin_nativePickModelPoint(
    JNIEnv* env,
    jobject,
    jstring pathValue,
    jint widthValue,
    jint heightValue,
    jdouble orbitXValue,
    jdouble orbitYValue,
    jdouble panXValue,
    jdouble panYValue,
    jdouble zoomValue,
    jboolean orthographicValue,
    jdouble screenXValue,
    jdouble screenYValue) {
  const std::string path = toString(env, pathValue);
  const int width = std::max(static_cast<int>(widthValue), 1);
  const int height = std::max(static_cast<int>(heightValue), 1);
  const float screenX = static_cast<float>(screenXValue);
  const float screenY = static_cast<float>(screenYValue);
  const auto mesh = meshForPath(path);
  if (mesh == nullptr || mesh->vertices.size() < 3 || !mesh->bounds.valid) return nullptr;

  const Vec3 center = mesh->bounds.center();
  const float extent = std::max(mesh->bounds.maxExtent(), 1.0e-3f);
  const float radius = extent * 0.6f;
  const float aspect = static_cast<float>(width) / static_cast<float>(height);
  const float safeZoom = std::clamp(static_cast<float>(zoomValue), 0.05f, 20.0f);
  const Mat4 model = multiply(
      multiply(rotationY(static_cast<float>(orbitXValue)), rotationX(static_cast<float>(orbitYValue))),
      translation(-center.x, -center.y, -center.z));

  Mat4 projection{};
  Mat4 view{};
  if (orthographicValue == JNI_TRUE) {
    const float halfHeight = std::max(radius * 1.35f / safeZoom, 1.0e-3f);
    const float halfWidth = halfHeight * aspect;
    projection = orthographic(-halfWidth, halfWidth, -halfHeight, halfHeight, -radius * 20.0f, radius * 20.0f);
    view = translation(
        static_cast<float>(panXValue) * extent * 2.0f,
        -static_cast<float>(panYValue) * extent * 2.0f,
        0.0f);
  } else {
    const float distance = std::max(radius * 3.2f / safeZoom, radius * 1.05f);
    const float nearPlane = std::max(radius * 0.01f, 1.0e-4f);
    const float farPlane = std::max(distance + radius * 20.0f, nearPlane + 1.0f);
    projection = perspective(45.0f * kPi / 180.0f, aspect, nearPlane, farPlane);
    view = translation(
        static_cast<float>(panXValue) * extent * 2.0f,
        -static_cast<float>(panYValue) * extent * 2.0f,
        -distance);
  }
  const Mat4 mvp = multiply(projection, multiply(view, model));

  float bestDepth = std::numeric_limits<float>::infinity();
  std::size_t bestTriangle = std::numeric_limits<std::size_t>::max();
  Vec3 bestPoint{};

  for (std::size_t first = 0; first + 2 < mesh->vertices.size(); first += 3) {
    if (!vertexVisible(*mesh, first)) continue;
    const std::array<const MeshVertex*, 3> vertex = {
        &mesh->vertices[first], &mesh->vertices[first + 1], &mesh->vertices[first + 2]};
    std::array<ScreenPoint, 3> screen{};
    bool projected = true;
    for (int i = 0; i < 3; ++i) {
      const ClipPoint clip = transform(mvp, vertex[i]->position);
      projected = projected && toScreen(clip, width, height, screen[i]);
    }
    if (!projected) continue;

    std::array<float, 3> bary{};
    if (!barycentric2d(screen[0], screen[1], screen[2], screenX, screenY, bary)) continue;
    const float depth = bary[0] * screen[0].z + bary[1] * screen[1].z + bary[2] * screen[2].z;
    if (!std::isfinite(depth) || depth >= bestDepth) continue;

    const float p0 = bary[0] * screen[0].reciprocalW;
    const float p1 = bary[1] * screen[1].reciprocalW;
    const float p2 = bary[2] * screen[2].reciprocalW;
    const float sum = p0 + p1 + p2;
    if (std::abs(sum) <= 1.0e-12f) continue;
    const float w0 = p0 / sum;
    const float w1 = p1 / sum;
    const float w2 = p2 / sum;
    bestPoint = {
        vertex[0]->position.x * w0 + vertex[1]->position.x * w1 + vertex[2]->position.x * w2,
        vertex[0]->position.y * w0 + vertex[1]->position.y * w1 + vertex[2]->position.y * w2,
        vertex[0]->position.z * w0 + vertex[1]->position.z * w1 + vertex[2]->position.z * w2,
    };
    bestDepth = depth;
    bestTriangle = first / 3;
  }

  if (bestTriangle == std::numeric_limits<std::size_t>::max()) return nullptr;

  // Auto-snap only against the front-most triangle already hit by the cursor.
  // This prevents mobile precision assistance from snapping through the visible
  // shell onto geometry behind it. These are tessellation features, not exact
  // OCCT topological vertices/edges.
  const std::size_t first = bestTriangle * 3;
  const Vec3 v0 = mesh->vertices[first].position;
  const Vec3 v1 = mesh->vertices[first + 1].position;
  const Vec3 v2 = mesh->vertices[first + 2].position;
  Vec3 snappedPoint = bestPoint;
  float snappedDepth = bestDepth;
  int snapCode = kSnapFree;
  float bestSnapDistance2 = kSnapRadiusPixels * kSnapRadiusPixels;

  auto considerSnap = [&](const Vec3& point, int code) {
    ScreenPoint candidate{};
    if (!toScreen(transform(mvp, point), width, height, candidate)) return;
    const float dx = candidate.x - screenX;
    const float dy = candidate.y - screenY;
    const float distance2 = dx * dx + dy * dy;
    if (!std::isfinite(distance2) || distance2 >= bestSnapDistance2) return;
    bestSnapDistance2 = distance2;
    snappedPoint = point;
    snappedDepth = candidate.z;
    snapCode = code;
  };

  // Candidate order gives a vertex precedence for exact distance ties, then
  // edge midpoint, then triangle center.
  considerSnap(v0, kSnapVertex);
  considerSnap(v1, kSnapVertex);
  considerSnap(v2, kSnapVertex);
  considerSnap(midpoint(v0, v1), kSnapEdgeMidpoint);
  considerSnap(midpoint(v1, v2), kSnapEdgeMidpoint);
  considerSnap(midpoint(v2, v0), kSnapEdgeMidpoint);
  considerSnap(centroid(v0, v1, v2), kSnapFaceCenter);

  const jdouble payload[6] = {
      static_cast<jdouble>(snappedPoint.x),
      static_cast<jdouble>(snappedPoint.y),
      static_cast<jdouble>(snappedPoint.z),
      static_cast<jdouble>(bestTriangle),
      static_cast<jdouble>(snappedDepth),
      static_cast<jdouble>(snapCode),
  };
  jdoubleArray result = env->NewDoubleArray(6);
  if (result == nullptr) return nullptr;
  env->SetDoubleArrayRegion(result, 0, 6, payload);
  return result;
}
