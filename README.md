# BrepSight

BrepSight is a **Flutter-first mobile universal engineering and 3D document workspace**. It is a clean rebuild rather than a patched Qt APK.

The goal is broader than a viewer: on a phone, users should be able to **capture -> open -> inspect -> fix -> convert -> hand off** engineering and 3D data without first finding a desktop workstation.

Primary domains include:

- mechanical CAD and B-Rep models;
- AutoCAD/drafting and Rhino/NURBS documents;
- polygonal/DCC scenes used by Blender and similar tools;
- FreeCAD documents;
- 3D printing, slicer and toolpath files;
- point clouds and scan/reverse-engineering data;
- BIM/AEC documents;
- CAE/FEM meshes and simulation result fields;
- optional bridges for proprietary CAD formats.

## Product lines

### Open and inspect

Recognize the file, choose the correct provider, preserve as much semantic data as possible, and show exactly what was lost or approximated.

### Capture

Use phone camera/depth capabilities or external scan data to build point clouds and reconstructed meshes. Initial outputs target PLY, OBJ, GLB, STL and 3MF. Reverse-engineered exact CAD is treated as fitted/approximate unless exact geometry truly exists.

### Convert

BrepSight acts as a loss-aware format transit station. Examples include STEP -> STL/3MF, 3DM -> GLB, scan mesh -> printable 3MF, and normalized CAE data -> VTK/VTU. Every conversion reports preserved and lost capabilities.

### Fix and hand off

Mobile-oriented operations include scale/unit checks, orientation, dimensions, mesh diagnostics/repair, simplification, point-cloud crop/downsample, print-volume checks, export and Android Share/Open-with flows.

See `docs/REAL_WORLD_WORKFLOWS.md` and `docs/INDUSTRY_FORMAT_MATRIX.md`.

## Architecture direction

BrepSight does not embed the old Qt CAD Assistant runtime and will not embed Blender or FreeCAD as monolithic applications. Independent providers feed a neutral engineering document model.

```text
Flutter / Material 3
        |
        v
Capture + Document + Conversion + Inspection services
        |
        +-- CAD/B-Rep provider ---- Open CASCADE
        +-- Drawing provider ------ DXF + optional DWG provider
        +-- Rhino provider -------- openNURBS
        +-- Mesh/DCC provider ----- Assimp + focused readers
        +-- Additive provider ----- lib3mf + toolpath readers
        +-- Scan provider --------- point-cloud/depth readers
        +-- FCStd provider -------- safe ZIP/XML/BREP reader
        +-- BIM provider ---------- dedicated IFC/AEC readers
        +-- CAE provider ---------- mesh/result readers
        +-- Proprietary bridge ---- optional licensed/conversion providers
        |
        v
Unified viewport + selection + measurement + repair + export
```

## What already exists

- Flutter Material 3 app shell with Chinese UI.
- Android system font fallback; no forced Open Sans UI font.
- Android system file picker and cache import flow.
- Flutter `Texture` viewport backed by `TextureRegistry.SurfaceProducer`.
- Kotlin lifecycle bridge.
- Native C++ EGL/OpenGL ES proof renderer with no Qt/QML runtime dependency.
- Viewer gestures and commands wired to native code.
- Industry format catalog separating native, planned, experimental and bridge-only support.
- Real-world capture/conversion workflow specification.
- GitHub Actions Android build line producing an installable debug APK artifact on every main/PR/manual build.
- OCCT-facing load command deliberately stubbed until a fresh Android OCCT build is linked.

## Important boundaries

- The original Qt-bound `libCADAssistant.so` is not copied into this project.
- Blender source is not linked into the Apache-2.0 core.
- FreeCAD document support is designed as safe read-only parsing; embedded Python/scripts are never executed.
- Proprietary formats are not falsely advertised as native-open formats.
- A scan mesh is not silently presented as recovered parametric CAD.
- BrepSight inspects toolpaths but never acts as a machine controller.

## Build

The repository pins Flutter 3.44.8 for reproducible CI builds.

```bash
bash tool/bootstrap_flutter.sh
flutter build apk --debug
```

`.github/workflows/android-apk.yml` performs the same Android build on GitHub-hosted runners and uploads the installable APK plus SHA-256 checksum. See `docs/BUILD_AND_RELEASE.md`.

## Current engine milestone

The next implementation milestone remains the shared foundation: neutral document/importer registry + Android OCCT. This is required before individual format providers can safely scale.
