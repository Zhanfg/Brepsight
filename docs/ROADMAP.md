# Roadmap

The roadmap optimizes for one rule: every milestone must leave BrepSight with a usable, testable mobile workflow instead of a large set of half-connected parsers.

## Continuous build line — Android APK on every change

This is not a late release task. From the current Stage 1 onward:

- every `main` push, pull request and manual dispatch runs the Android APK workflow;
- Flutter is pinned to 3.44.8 stable for reproducibility;
- CI runs analysis/tests where present;
- CI builds a debug-signed installable APK;
- APK + SHA-256 are uploaded as Actions artifacts;
- Android/native build changes are not considered complete until this workflow passes.

Production signing is a separate protected release line using an owner-controlled stable key; signing secrets must never be committed or logged.

## Stage 2 — native document foundation

Goal: replace the proof renderer with a real engineering document pipeline.

- Build Android arm64 Open CASCADE without Qt.
- Introduce native importer registry and capability report.
- Introduce neutral scene/document handles.
- Render a generated B-Rep box.
- Add stable native document lifetime and cancellation API.
- Add import progress/error events.
- Keep Flutter API independent of a particular importer.
- Define exporter/writer registry beside the importer registry so conversion does not become a second unrelated architecture.

Exit criteria:

- generated shape renders;
- camera/selection survives surface recreation;
- malformed import cannot crash the app process in basic fuzz smoke tests;
- a normalized document can report which output writers are valid without inspecting the original filename again.

## Stage 3 — universal engineering baseline

Goal: make BrepSight useful across the most common CAD, 3D-printing and mobile inspection workflows before chasing proprietary native files.

Baseline import order:

1. STL
2. STEP/XCAF
3. IGES
4. BREP
5. glTF/GLB
6. OBJ
7. **3MF through lib3mf**
8. **AutoCAD DXF through a BrepSight read-only parser**
9. **Rhino `.3dm` through openNURBS**
10. PLY
11. VRML

The three bold items are baseline formats, not long-tail additions:

- 3MF is the preferred rich additive-manufacturing container;
- DXF covers a large drafting/AutoCAD exchange surface without requiring a proprietary DWG decoder;
- 3DM gives BrepSight first-class access to the Rhino/NURBS ecosystem, including Rhino 8 files.

Viewer services:

- assembly/object tree;
- drawing layers/blocks where applicable;
- fit/view presets;
- shaded/edges/wireframe;
- names/colors/layers;
- bounding box and dimensions;
- distance/angle/radius;
- area/volume;
- section plane;
- import diagnostics and capability-loss report.

Exit criteria:

- real multi-part STEP assembly opens on Android;
- one 3MF manufacturing package opens with units/build items preserved;
- representative DXF opens with layers and blocks;
- representative Rhino 8 3DM opens with hierarchy/attributes and viewable geometry;
- object tree visibility works;
- measurements are topology-aware for exact CAD data.

## Stage 3A — AutoCAD/DWG optional provider

Goal: recognize AutoCAD-native workflows without making a commercial SDK mandatory for the open build.

- Keep native DXF in the open core.
- Define `drawing.dwg` provider ABI.
- Support an optional ODA Drawings SDK provider on Android where licensing permits.
- Keep LibreDWG out of the default Apache APK; a GPL companion/converter may be evaluated separately.
- Normalize layers, blocks, model/paper space, text/dimensions and 3D entities into the shared drawing/document model.

## Stage 3B — Rhino exact-geometry progression

Goal: move beyond merely showing Rhino render meshes.

- openNURBS v1-v8+ reader.
- Saved render mesh path for immediate viewing.
- Layers, object attributes, instance definitions, materials and annotations.
- Progressive conversion of supported ON_Curve / ON_Surface / ON_Brep entities into the neutral/OCCT exact-geometry layer.
- SubD initially uses saved render representation where available; exact conversion is a separate capability.

## Stage 4 — FreeCAD document provider

Goal: open useful FCStd documents safely without embedding FreeCAD.

- ZIP preflight and extraction limits.
- Safe `Document.xml` parser.
- Supported `GuiDocument.xml` metadata.
- Stored BREP/BRP extraction through OCCT.
- Placements, labels, hierarchy, colors/visibility where recoverable.
- Thumbnail extraction.
- Unsupported-object diagnostics.
- Explicitly reject script execution and unsafe serialized Python restore.

Exit criteria:

- ordinary Part/PartDesign FCStd documents display stored geometry and tree structure;
- malicious script-bearing FCStd files are treated only as data.

## Stage 5 — DCC / Blender ecosystem pack

Goal: make the phone useful for models coming from Blender, DCC and visualization workflows.

Initial Assimp-backed targets:

- FBX
- Collada/DAE
- 3DS
- OFF/GTS and other proven mesh formats after corpus testing

Dedicated providers:

- USD/USDZ
- Alembic

Native `.blend` remains experimental until there is a maintainable reader/bridge with clear license boundaries.

Exit criteria:

- representative FBX/DAE models open with hierarchy and materials;
- unsupported scene features are reported instead of silently dropped.

## Stage 5A — additive manufacturing and toolpath inspection

Goal: cover files that exist after CAD but before/at the printer.

- 3MF extension capability reporting (materials, production, slices and vendor namespaces where understood).
- AMF reader.
- G-code toolpath viewer with layers, extrusion, travel, temperatures and time metadata.
- Binary G-code where the revision is documented.
- CLI/SLC slice contour preview.
- Experimental vendor-specific resin slice preview providers.
- Never execute or transmit machine commands automatically.

## Stage 6 — CAE / simulation core

Goal: view simulation meshes and results, not solve them.

Neutral result model:

- nodes/elements;
- named sets;
- scalar/vector/tensor fields;
- node/element association;
- load cases and time steps;
- deformation vectors;
- units and source metadata.

First readers:

1. VTK legacy
2. VTU/VTP/PVD
3. Gmsh MSH
4. CalculiX FRD
5. Abaqus INP
6. NASTRAN BDF

Viewer services:

- contour map;
- legend;
- min/max;
- point probe;
- deformed/undeformed toggle;
- deformation scale;
- field/component selection;
- time-step playback.

Exit criteria:

- one structural result and one thermal/scalar dataset can be inspected on-device with consistent UI.

## Stage 7 — point clouds, scan and very large datasets

- E57.
- LAS/LAZ.
- PCD.
- XYZ/PTS/PTX/ASC table probing.
- chunked streaming and LOD;
- point color/intensity modes;
- clipping and large-file memory budgets;
- GPU path for very large triangle/CAE datasets;
- partial/lazy loading;
- background import process isolation.

## Stage 7A — phone capture / scan-to-model

Goal: let the phone create useful 3D data rather than only consume it.

- ARCore Depth capability probe and capture path;
- Raw Depth + confidence capture for reconstruction-oriented devices/workflows;
- RGB + camera pose capture for photogrammetry-oriented reconstruction;
- point-cloud accumulation with scale/coordinate metadata;
- bounded-memory reconstruction pipeline;
- cleanup/crop/downsample before meshing;
- mesh + texture preview;
- PLY/OBJ/GLB/STL/3MF outputs;
- graceful fallback on devices without Depth support.

Reverse-engineering extensions may fit planes/cylinders/surfaces and create approximate B-Rep, but output must state fitting tolerance and must never be described as recovered original parametric history.

Exit criteria:

- one supported Android device can capture a small object/scene into a point cloud or mesh;
- exported output reopens in BrepSight;
- output scale/confidence is reported;
- unsupported hardware falls back safely.

## Stage 7B — format conversion workspace

Goal: turn the shared neutral document into a practical mobile format transit station.

P0 writers:

- STL;
- OBJ;
- glTF/GLB;
- PLY;
- 3MF.

P1 writers:

- STEP for valid exact/fitted B-Rep sources;
- DXF supported drawing/curve subsets;
- VTK/VTU normalized CAE data;
- point-cloud interchange.

Every conversion emits a structured loss report. Outputs can be reopened for verification before Android Share/export handoff.

## Stage 7C — BIM / AEC

- IFC/IFCZIP/IFCXML provider with object identity and properties preserved.
- BCF collaboration metadata.
- DGN provider evaluation.
- Revit remains bridge-only unless a redistributable provider is available.
- triangle-only IFC does not count as full BIM support.

## Stage 8 — extended scientific/manufacturing formats

- CGNS / Exodus II / MED / OpenFOAM.
- NASTRAN OP2/F06.
- ANSYS CDB and optional result bridges.
- LS-DYNA keyword/result providers.
- OpenVDB/volumetric inspection.
- STEP-NC / APT / CL toolpath families.

## Stage 9 — proprietary CAD bridges

Formats such as native SOLIDWORKS, Inventor, Fusion, CATIA, Creo, NX, Solid Edge, Revit, ACIS/Parasolid and solver result databases are handled only when one of these conditions is true:

1. a legally redistributable reader is available;
2. the user supplies/enables an optional licensed SDK provider;
3. a desktop helper converts through the user's installed/licensed application.

The open mobile core must remain useful without any proprietary provider.

A future `brepsight-convert` desktop helper may provide conversion for these formats while preserving the mobile core's license boundary.

## Test strategy across all stages

Every new importer/writer/capture path needs the relevant subset of:

- minimal valid fixture;
- representative real-world fixture where licensing permits;
- malformed/truncated fixture;
- oversized/allocation-limit fixture;
- capability expectation file;
- import -> normalized document assertions;
- normalized document -> export -> reopen assertions;
- conversion-loss expectation;
- screenshot/geometry sanity check for selected fixtures;
- regression fixture for every parser crash fixed;
- Android APK workflow green before integration.

See also `docs/INDUSTRY_FORMAT_MATRIX.md`, `docs/REAL_WORLD_WORKFLOWS.md`, and `docs/BUILD_AND_RELEASE.md`.
