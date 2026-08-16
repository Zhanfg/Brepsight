# Roadmap

The roadmap optimizes for one rule: every milestone must leave BrepSight with a usable, testable viewer instead of a large set of half-connected parsers.

## Stage 2 — native document foundation

Goal: replace the proof renderer with a real engineering document pipeline.

- Build Android arm64 Open CASCADE without Qt.
- Introduce native importer registry and capability report.
- Introduce neutral scene/document handles.
- Render a generated B-Rep box.
- Add stable native document lifetime and cancellation API.
- Add import progress/error events.
- Keep Flutter API independent of a particular importer.

Exit criteria:

- generated shape renders;
- camera/selection survives surface recreation;
- malformed import cannot crash the app process in basic fuzz smoke tests.

## Stage 3 — CAD core

Goal: make BrepSight genuinely useful for engineering files.

Order:

1. STL
2. STEP/XCAF
3. IGES
4. BREP
5. glTF/GLB
6. OBJ
7. VRML
8. PLY through mesh provider

Viewer services:

- assembly/object tree;
- fit/view presets;
- shaded/edges/wireframe;
- names/colors/layers;
- bounding box and dimensions;
- distance/angle/radius;
- area/volume;
- section plane;
- import diagnostics.

Exit criteria:

- real multi-part STEP assembly opens on Android;
- object tree visibility works;
- measurements are topology-aware for CAD data.

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

Goal: make the phone useful for models coming from Blender, DCC and game/visualization workflows.

Initial Assimp-backed targets:

- FBX
- Collada/DAE
- 3DS
- PLY
- OFF
- 3MF
- additional proven Assimp formats after corpus testing

Preserve where possible:

- hierarchy/transforms;
- normals/tangents;
- materials/textures;
- cameras;
- basic animation metadata.

Dedicated providers later:

- USD/USDZ
- Alembic

Native `.blend` remains experimental until there is a maintainable reader/bridge with clear license boundaries.

Exit criteria:

- representative FBX/DAE/3MF models open with hierarchy and materials;
- unsupported scene features are reported instead of silently dropped.

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

## Stage 7 — large files and optional providers

- GPU path for very large triangle/CAE datasets.
- partial/lazy loading.
- background import process isolation.
- CGNS / Exodus II / OpenFOAM providers.
- dedicated IFC/BIM provider if needed.
- optional licensed Parasolid/native CAD provider interface.
- optional desktop `brepsight-convert` helper for formats that cannot be legally/reliably parsed in the open Android core.

## Stage 8 — proprietary bridges

Formats such as native SOLIDWORKS documents and `.CWR` simulation databases are handled only when one of these conditions is true:

1. a legally redistributable reader is available;
2. the user supplies/enables an optional licensed SDK provider;
3. a desktop helper converts through the user's installed/licensed application.

The open mobile core must remain useful without any proprietary provider.

## Test strategy across all stages

Every new importer needs:

- minimal valid fixture;
- representative real-world fixture where licensing permits;
- malformed/truncated fixture;
- oversized/allocation-limit fixture;
- capability expectation file;
- import -> normalized document assertions;
- screenshot/geometry sanity check for selected fixtures;
- regression fixture for every parser crash fixed.
