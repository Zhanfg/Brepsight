#pragma once

#include <string>

#include "mesh_document.h"

namespace brepsight {

struct SectionPlane {
  bool enabled = false;
  Vec3 normal{0.0f, 0.0f, 1.0f};
  float offset = 0.0f;
};

// Stores the process-wide display section plane used by the mobile viewer.
// Exact provider payloads remain untouched; only the GLES display mesh is
// clipped on the next load/reload.
bool setActiveSectionPlane(
    bool enabled,
    Vec3 normal,
    float offset,
    std::string& error);

SectionPlane activeSectionPlane();

// Clips triangles against the active half-space and rebuilds draw ranges and
// bounds. Crossing triangles are geometrically split instead of only hidden by
// centroid, so the visible section boundary is stable under camera motion.
bool applyActiveSectionPlane(MeshData& mesh, std::string& error);

}  // namespace brepsight
