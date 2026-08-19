# BrepSight 0.1 acceptance ledger

This file is the release-specific source of truth for the `0.1` consolidation branch. It records what the implementation and CI prove; it does not substitute CI success with roadmap intent.

## Product baseline

- Android package: `dev.brepsight`
- Version line: `0.1.0`
- Android baseline: arm64-v8a, minSdk 24
- Product mode: read / inspect. No source-format write-back is claimed by 0.1.

## Import capability gates

| Capability | 0.1 status | Evidence contract |
|---|---|---|
| STL | validated | native importer regression in Android APK workflow |
| OBJ | validated | native importer regression in Android APK workflow |
| BREP / BRP | validated exact geometry | OCCT semantic/provider regression |
| STEP / STP | validated exact geometry | OCCT/XCAF provider semantics + Android packaging |
| IGES / IGS | validated exact geometry | pinned OCCT generates a real IGES box, then BrepSight re-imports it and checks exact payload, tessellation, hierarchy and dimensions |
| 3MF | validated read-only core subset | lib3mf semantic/provider regressions + Android packaging |
| FCStd | validated read-only saved-geometry subset | hardened ZIP/XML preprocessing + saved BREP path; no FreeCAD runtime or recompute |
| DAE | validated mesh/scene subset | clean-room Assimp semantic smoke |
| PLY | validated mesh subset | clean-room Assimp semantic smoke |
| OFF | validated mesh subset | clean-room Assimp semantic smoke |
| FBX | validated mesh/scene subset | pinned Assimp 6.0.5 fixture semantic smoke |
| glTF | validated mesh/scene subset | pinned Assimp 6.0.5 fixture semantic smoke, including UV preservation |
| GLB | validated mesh/scene subset | pinned Assimp 6.0.5 fixture semantic smoke, including UV preservation |
| 3DS | validated mesh/scene subset | pinned Assimp 6.0.5 fixture semantic smoke |
| DXF | validated Assimp-supported subset | pinned Assimp 6.0.5 fixture semantic smoke; this is not a full AutoCAD/DWG fidelity claim |
| Rhino 3DM | validated saved/render-mesh subset | pinned openNURBS generates a real `.3dm`, then BrepSight re-imports it and checks mesh, bounds, object counts and stable source identity |

### Explicit 3DM boundary

BrepSight 0.1 does **not** claim full Rhino NURBS/BRep/history support. The 3DM provider consumes saved `ON_Mesh` geometry that exists in the document and reports/skips unsupported non-mesh geometry. This is intentionally a read-only saved/render-mesh subset.

### Explicit DCC boundary

Assimp-backed formats are read-only interchange subsets. Scene hierarchy/transforms and the metadata that BrepSight retains are validated where covered by the fixtures, but this does not imply application-document fidelity, animation playback, full material graphs, or native `.blend` support.

## Viewer/tooling gates

| Capability | 0.1 status | Evidence contract |
|---|---|---|
| Orbit / pan / zoom / projection | implemented | viewer integration |
| Stable pick identity | validated | point identity is scoped as `documentHandle:triangleIndex`; Dart regression locks the contract |
| Mesh selection filters | validated tessellation subset | vertex / edge / face / body filtering, renderer highlight, and local properties regression |
| Distance measurement | validated | known 3-4-5 result regression |
| Angle measurement | validated | known 90-degree result + degenerate rejection regression |
| Radius measurement | validated | known unit circumcircle + collinear rejection regression |
| Coordinate / area measurement | validated UI/API path | narrow-screen viewer regression and stable pick path |
| Section plane | validated | native regression clips crossing geometry, rebuilds bounds and preserves draw-range identity |
| Exploded assembly view | validated display-only transform | per-object draw-range offsets are applied in the renderer; selection/measurement are blocked while exploded so stable geometry identities are not misreported |
| Persistent local annotations | validated local/offline path | model-scoped unsigned 64-bit content identity, JSON persistence, optional stable geometry anchor, optional bounded PNG thumbnail, narrow-screen UI regressions |
| Import progress | validated API contract | Dart MethodChannel regression for stage/progress/task identity |
| Import cancellation | validated API/state path | cancellation request and previous-document restoration are wired; native document replacement removes the superseded record transactionally |
| Section UI | implemented | X/Y/Z plane and coordinate control wired to native clipping |
| Measurement UI | implemented | distance/angle/radius/coordinate/area selection modes wired to model picking |

### Explicit viewer boundaries

- Vertex/edge selection currently snaps against front-surface **tessellation** candidates. Exact OCCT topological vertex/edge snap is not claimed by 0.1.
- Exploded view is a display transform. It does not rewrite exact geometry or source assembly transforms.
- Local annotations are intentionally device-local in 0.1. They are not a cloud collaboration or account-sync feature.
- Annotation anchors are only re-applied in the unedited, unsectioned, unexploded display state so a stored stable identity is not falsely projected onto altered display geometry.

## Packaging gates

A release-candidate APK is acceptable for device testing only when all of these are true on the same branch head:

- Flutter/Dart tests pass, including `test/v01_tools_test.dart`;
- Android plugin/JVM tests pass;
- native mesh/section tests pass;
- OCCT, lib3mf, Assimp and openNURBS provider SDKs stage successfully;
- debug APK compiles for `android-arm64`;
- `libcad_engine.so` is packaged;
- enabled provider shared libraries are packaged and linked;
- no armeabi-v7a provider payload is present;
- APK checksum and build-info are emitted as an Actions artifact.

## Engineering acceptance

Final product validation head before this ledger-only update: `3137f04060cd0fc92e23edce48a08fac788b01fa`.

- [x] Assimp pinned semantic coverage: FBX / glTF / GLB / 3DS / DXF
- [x] Assimp clean-room semantic coverage: DAE / PLY / OFF
- [x] Rhino 3DM generated-fixture saved-mesh semantic contract
- [x] IGES generated-fixture exact-geometry semantic contract
- [x] Native section-plane clipping regression
- [x] Measurement/stable-pick/progress/cancel API regressions in the Android release workflow
- [x] Renderer-native exploded assembly view + focused narrow-screen regression
- [x] Persistent local/offline annotations + model identity/codec/narrow-screen regressions
- [x] Final same-head Android APK workflow green and artifact published

Evidence on `3137f04060cd0fc92e23edce48a08fac788b01fa`:

- `Android APK` #357 — success; artifact `brepsight-apk-357`
- `Mesh Edit Core` #91 — success
- `Assimp DCC Provider Smoke` #170 — success
- `openNURBS 3DM Provider Smoke` #104 — success
- `OCCT IGES Semantic Smoke` #108 — success

The APK artifact from Android run #357 is tied to that exact source head and carries Actions artifact digest `sha256:679251e39064472a7b18b08e81cb61ce5c3bf3d4388fa3f395f552f3d8970830`.

## Device acceptance

CI engineering acceptance is complete. Device-open and interaction acceptance remains a real-device gate and is deliberately **not** inferred from CI. The RC APK should be installed and checked for launch, representative model open, touch camera, selection/measurement, section plane, exploded view, local annotation persistence, and background/import cancellation behavior.

A formal `v0.1.0` tag/release follows successful device acceptance rather than preceding it.
