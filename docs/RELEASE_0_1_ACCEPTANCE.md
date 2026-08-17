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
| IGES / IGS | pending final semantic run | pinned OCCT generates a real IGES box, then BrepSight re-imports it and checks exact payload, tessellation, hierarchy and dimensions |
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
| Distance measurement | validated | known 3-4-5 result regression |
| Angle measurement | validated | known 90-degree result + degenerate rejection regression |
| Radius measurement | validated | known unit circumcircle + collinear rejection regression |
| Section plane | validated | native regression clips crossing geometry, rebuilds bounds and preserves draw-range identity |
| Import progress | validated API contract | Dart MethodChannel regression for stage/progress/task identity |
| Import cancellation | validated API/state path | cancellation request and previous-document restoration are wired; native document replacement removes the superseded record transactionally |
| Section UI | implemented | X/Y/Z plane and coordinate control wired to native clipping |
| Measurement UI | implemented | distance/angle/radius selection modes wired to model picking |

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

## Acceptance remaining before user test

- [x] Assimp pinned semantic coverage: FBX / glTF / GLB / 3DS / DXF
- [x] Assimp clean-room semantic coverage: DAE / PLY / OFF
- [x] Rhino 3DM generated-fixture saved-mesh semantic contract
- [x] Native section-plane clipping regression
- [x] Measurement/stable-pick/progress/cancel API regressions added to the Android release workflow
- [ ] IGES generated-fixture exact-geometry semantic contract green on the final branch head
- [ ] Final same-head Android APK workflow green and artifact published

## Device acceptance

Device-open and interaction acceptance is deliberately **not** checked here by CI. After the engineering gates above are green, the generated RC APK is handed to the user for real-device testing. A formal `v0.1.0` tag/release should follow that device acceptance rather than precede it.
