# BrepSight

BrepSight is a **Flutter-first mobile engineering model viewer and inspection toolkit**. It is a clean rebuild rather than a patched Qt APK.

The project is intentionally broader than a basic STL/CAD viewer. The long-term target is to open and inspect as many useful engineering files as practical on Android across:

- mechanical CAD and B-Rep models;
- polygonal/DCC scenes used by Blender and similar tools;
- FreeCAD documents;
- exchange formats produced by SOLIDWORKS and other commercial CAD systems;
- CAE/FEM meshes and simulation result fields.

Editing and solving are secondary. The first priority is **open -> inspect -> measure -> understand** on a phone.

## Architecture direction

BrepSight does not embed the old Qt CAD Assistant runtime and will not embed Blender or FreeCAD as monolithic applications. Instead it uses independent importer providers feeding a neutral engineering scene model.

```text
Flutter / Material 3
        |
        v
Document + inspection services
        |
        +-- CAD/B-Rep provider ---- Open CASCADE
        +-- Mesh/DCC provider ----- Assimp + focused readers
        +-- FCStd provider -------- safe ZIP/XML/BREP reader
        +-- CAE provider ---------- mesh/result readers
        +-- Proprietary bridge ---- optional licensed/conversion providers
        |
        v
Unified native viewport + selection + measurement + result visualization
```

See `docs/ARCHITECTURE.md` and `docs/FORMAT_SUPPORT.md` for the detailed boundary.

## What already exists

- Flutter Material 3 app shell with Chinese UI.
- Android system font fallback; no forced Open Sans UI font.
- Android system file picker and cache import flow.
- Flutter `Texture` viewport backed by `TextureRegistry.SurfaceProducer`.
- Kotlin lifecycle bridge.
- Native C++ EGL/OpenGL ES proof renderer with no Qt/QML runtime dependency.
- Viewer gestures and commands wired to native code.
- A format catalog that separates planned native support from experimental and bridge-only formats.
- OCCT-facing load command deliberately stubbed until a fresh Android OCCT build is linked.

## Important boundaries

- The original Qt-bound `libCADAssistant.so` is not copied into this project.
- Blender source is not linked into the Apache-2.0 core.
- FreeCAD document support is designed as safe read-only parsing; embedded Python/scripts are never executed.
- Native SOLIDWORKS files and Simulation databases are not falsely advertised as open-source-compatible formats. Where no safe open reader exists, BrepSight uses exchange formats or an optional bridge.

## Next implementation step

Build the neutral document/importer layer, then replace the proof renderer with a clean OCCT-backed viewport. The first real import sequence is:

1. STL
2. STEP/XCAF
3. IGES/BREP/glTF/OBJ
4. FCStd read-only geometry extraction
5. DCC mesh formats
6. CAE mesh/result formats

## Build

A current Flutter + Android SDK/NDK environment is required:

```bash
bash tool/bootstrap_flutter.sh
flutter build apk --debug
```

The repository currently contains the Stage 1 Flutter shell and native rendering bridge. A fresh Android OCCT build and the importer registry are the next engine milestones.
