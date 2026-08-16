# Architecture

## Product boundary

BrepSight is a mobile engineering viewer, not a mobile clone of one desktop CAD suite. The core job is to normalize different engineering documents into a common inspection model while preserving domain-specific information when possible.

The app must be able to represent four different payload families without forcing everything through one lossy mesh conversion:

1. **B-Rep CAD** — exact solids/surfaces, assemblies, names, colors, layers and PMI where available.
2. **Mesh/DCC scenes** — polygon meshes, transforms, materials, textures, cameras and animation metadata.
3. **CAE models/results** — nodes/elements plus scalar, vector and tensor fields, sets, load cases and time steps.
4. **Document metadata** — units, hierarchy, properties, source application and import diagnostics.

## Target stack

```text
Flutter / Dart
├─ Material 3 UI
├─ file flow / recent models / settings
├─ inspection panels
├─ format capability UI
├─ gesture layer
└─ Texture widget
       │ textureId
       ▼
Android Flutter plugin (Kotlin)
├─ TextureRegistry.SurfaceProducer
├─ Android Storage Access Framework
├─ import worker orchestration
└─ lifecycle + JNI bridge
       │ Surface / commands / document events
       ▼
C++ native core
├─ document model
│  ├─ scene tree + transforms
│  ├─ B-Rep payload handles
│  ├─ mesh/line/point payloads
│  ├─ metadata + units
│  └─ CAE result fields + time steps
│
├─ importer registry
│  ├─ OCCT provider
│  ├─ mesh/DCC provider
│  ├─ FCStd safe provider
│  ├─ CAE provider
│  └─ optional proprietary bridge providers
│
├─ inspection services
│  ├─ selection
│  ├─ measurements
│  ├─ section/clipping
│  ├─ topology/mesh diagnostics
│  └─ result probing / min-max / legends
│
└─ render coordinator
   ├─ Stage 1: EGL/OpenGL ES proof renderer
   ├─ CAD path: OCCT V3d_Viewer + AIS_InteractiveContext
   └─ high-volume mesh/result path: GPU mesh layer when required
```

## Importer registry

Flutter must not contain format-specific parsing logic. Each native importer advertises:

- stable provider id;
- accepted extensions/MIME hints;
- domain: CAD, mesh/DCC, FCStd, CAE or proprietary bridge;
- capabilities: geometry, hierarchy, materials, PMI, animation, results, time series;
- confidence and diagnostics;
- whether parsing is built-in, experimental or bridge-only.

The registry probes by file signature/content where practical instead of trusting only the extension.

A failed importer must not crash the app or leave a partially committed document. Import happens into a temporary document and becomes visible only after validation succeeds.

## CAD provider

Open CASCADE remains the exact-geometry kernel. It is responsible for B-Rep, STEP/XCAF, IGES and other formats supported by the open OCCT data-exchange modules.

OCCT is a provider, not the entire BrepSight architecture. Mesh/DCC and CAE data should not be forced through TopoDS shapes when that would lose useful scene or result information.

## Mesh / DCC provider

Use a permissively licensed asset importer for broadly documented exchange formats such as FBX, Collada, 3DS, PLY, OFF and similar formats. Assimp is the initial candidate because it has an Android port and a 3-clause BSD-style license.

Native `.blend` is treated separately. Blender's file is an application document rather than a stable interchange format, and current Assimp documentation marks BLEND support as deprecated. BrepSight therefore does not claim full-fidelity `.blend` support until an independently maintainable reader or optional bridge exists.

## FreeCAD provider

`.FCStd` support does not require embedding the full FreeCAD desktop application. FCStd is a ZIP container whose document metadata is stored in XML and whose saved Part shapes are stored as BREP payloads.

The BrepSight FCStd provider is read-only and extracts saved geometry, hierarchy, labels and supported display metadata. It does **not** recalculate the parametric model and does not execute embedded Python, macros or serialized Python objects.

## CAE provider

Simulation viewing is a first-class domain rather than an afterthought. The document model must support:

- node- and element-based meshes;
- beam/shell/solid element families;
- named sets;
- scalar fields such as stress magnitude, temperature and displacement magnitude;
- vector fields such as displacement/velocity;
- tensor fields when supplied;
- multiple load cases and time steps;
- deformed-shape scale;
- contour legends and probe values.

Initial open formats are listed in `FORMAT_SUPPORT.md`. Proprietary result databases such as SOLIDWORKS Simulation `.CWR` are bridge-only unless a legally redistributable reader becomes available.

## Rendering

Use Flutter's Android `TextureRegistry.SurfaceProducer` and hand the produced Android `Surface` to native C++.

The renderer must keep a stable viewport API while allowing different internal paths:

- OCCT handles exact CAD/B-Rep visualization, topology-aware selection and sectioning.
- Mesh/result data can initially render through OCCT-compatible presentation objects.
- A dedicated GPU mesh/result renderer can be introduced later for very large DCC/CAE datasets without rewriting Flutter.

## Command split

- Low-frequency UI commands: MethodChannel initially.
- High-frequency camera/selection/probe traffic: C ABI + Dart FFI when the native scene model is active.
- Long-running import/meshing: C++ worker thread or isolated Android worker; progress/events returned asynchronously.

## Security boundary

Engineering files are untrusted input.

- Never execute embedded scripts/macros while importing.
- Disable XML external entity resolution.
- Apply ZIP entry count, decompressed-size and compression-ratio limits.
- Apply parser depth/allocation limits before constructing large scenes.
- Keep source files read-only and write conversions only to app-controlled cache.
- Risky/experimental importers should be movable to an isolated Android process without changing Flutter APIs.

See `SECURITY_MODEL.md`.

## Fonts

No bundled application UI font. Flutter/Android system typography is used, allowing native CJK fallback. CAD annotation fonts are a separate concern inside the renderer and must not be replaced by the UI font.
