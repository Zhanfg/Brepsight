# Format support strategy

BrepSight targets broad **read/inspect** coverage rather than pretending every format is equally supported. Each format belongs to one of four support classes:

- **First-class native** — intended to open offline on Android with a maintained in-process provider.
- **Planned native** — technically suitable for an open provider, but not part of the first importer milestones.
- **Experimental** — format is unstable, poorly documented, or available only through a weak reader.
- **Bridge only** — no legally redistributable, maintainable open reader is available; use an optional licensed provider or conversion workflow.

The UI must show the class and any lost capabilities instead of reporting a generic success. A provider is not considered fully supported merely because it compiles: Android APK integration and representative fixture tests are separate gates.

## 1. CAD / exact geometry

### First-class native

| Format | Extensions | Initial provider | Notes |
|---|---|---|---|
| STEP | `.stp`, `.step`, `.stepz` | Open CASCADE | Prefer XCAF path for assembly/name/color/layer metadata and AP242 where available. |
| IGES | `.igs`, `.iges` | Open CASCADE | Exact surface/B-Rep import. |
| Open CASCADE BREP | `.brep`, `.brp` | Open CASCADE | Direct exact provider is now implemented and semantic-tested; also used by FreeCAD saved shapes. |
| XCAF document | `.xbf` | Open CASCADE | Native OCCT document representation. |
| STL | `.stl` | Open CASCADE / mesh provider | Mesh-only; diagnostics and unit warning required. |
| OBJ | `.obj` | Open CASCADE / mesh provider | Mesh/material path. |
| glTF 2.0 | `.gltf`, `.glb` | Open CASCADE / mesh provider | Scene/material-friendly exchange. |
| VRML | `.wrl`, `.vrml` | Open CASCADE | Legacy scene/mesh exchange. |
| PLY | `.ply` | mesh provider | Read through the mesh provider; current OCCT DE wrapper exposes PLY write but not read. |

### Planned / optional

| Format | Policy |
|---|---|
| DXF/DWG | 2D/3D scope must be explicit. Prefer a dedicated permissive reader for supported subsets; do not imply full AutoCAD compatibility. |
| IFC | Prefer a dedicated BIM-capable provider when metadata/relationships matter; a triangle-only import is insufficient. |
| 3DM | Dedicated provider candidate. |
| JT | Optional provider; full fidelity may require commercial technology. |
| Parasolid `.x_t/.x_b` | Optional licensed provider. The open OCCT base does not include the commercial Parasolid translator. |

## 2. FreeCAD

### FCStd: first-class read-only target

`.FCStd` is a ZIP-based document container. A saved document typically contains:

- `Document.xml` — object/document data;
- `GuiDocument.xml` — visual metadata;
- one or more stored BREP/BRP shapes;
- optional thumbnails and embedded resources.

BrepSight can therefore provide useful mobile viewing without embedding or starting FreeCAD itself.

### Current implemented subset

The current provider is intentionally narrower than the full target. It is a **safe, read-only saved-geometry reader**:

1. the Android layer validates FCStd ZIP entry count, sizes, compression ratios and normalized paths before extraction;
2. `Document.xml` is parsed as data with DTD/external-entity/network resolution disabled;
3. only BREP/BRP members explicitly referenced by `Part::PropertyPartShape` are extracted;
4. extracted saved shapes are loaded through the OCCT exact BREP provider and aggregated into the engineering document;
5. object names and aggregate object counts are retained where available;
6. the temporary extraction directory is removed after native materialization;
7. Python, macros, pickle data and parametric recompute are never executed.

This subset has separate JVM malicious-container fixtures, a clean-room real-BREP/FCStd semantic smoke, and Android APK integration coverage. It must still be reported as **partial FCStd fidelity** because the following are not yet reconstructed:

- complete FreeCAD object tree relationships;
- placements/transforms from document metadata;
- `GuiDocument.xml` colors and visibility;
- thumbnails and richer presentation metadata;
- comprehensive unsupported-workbench diagnostics.

### Full target behavior

1. validate ZIP limits before extraction;
2. parse XML with external entities disabled;
3. build the document/object hierarchy;
4. load stored BREP geometry through OCCT;
5. apply supported labels, placements, colors and visibility metadata;
6. extract thumbnail if present;
7. report unsupported object types without failing the whole document.

Deliberate non-goals:

- no Python execution;
- no macro execution;
- no unpickling/serialized Python object restore;
- no parametric recompute;
- no attempt to behave as a complete FreeCAD workbench host.

This keeps FCStd useful and safe as a viewer format.

## 3. Blender / DCC ecosystem

BrepSight should support the **Blender interchange ecosystem** strongly even if native `.blend` remains difficult.

### First-class/planned mesh provider

Assimp is the initial candidate for broad DCC import because it is C/C++, supports Android, uses a permissive 3-clause BSD-style license, and currently documents 40+ import formats.

High-value targets:

- FBX
- Collada / DAE
- 3DS
- PLY
- OFF
- OBJ
- STL
- BVH
- glTF/GLB
- selected DXF/IFC mesh paths where appropriate

BrepSight should normalize:

- node hierarchy;
- transforms;
- polygon meshes;
- normals/tangents;
- materials/textures;
- cameras where useful;
- basic animation metadata where the provider exposes it reliably.

### Native `.blend`

`.blend` is **experimental**, not a launch promise.

Reasons:

- it is Blender's application document, not a simple interchange format;
- compatibility logic changes with Blender versions;
- current Assimp documentation marks BLEND import as deprecated because maintaining an undocumented, feature-rich application format is expensive;
- linking Blender itself into BrepSight would introduce GPL obligations and an impractical mobile runtime footprint.

Possible future routes:

1. independently maintained read-only `.blend` geometry reader;
2. separate optional GPL companion/bridge;
3. desktop conversion helper using installed Blender;
4. encourage glTF/USD/FBX export where full direct reading is not reliable.

The UI must distinguish "Blender ecosystem supported" from "full native .blend fidelity".

## 4. Additive manufacturing / 3MF

`.3mf` is a **first-class native target** through the optional lib3mf provider. BrepSight does not treat 3MF as a renamed STL because the container carries model units, object resources, build items, transforms and extension metadata.

### Initial provider scope

The first Android provider supports the 3MF Core geometry path:

- model unit preservation;
- build-item identity and transforms;
- mesh-object vertices and triangles;
- nested Components objects and component transforms;
- recursive hierarchy accounting;
- cycle/depth/expanded-object guards;
- display tessellation normalized to millimeters;
- mirrored transforms with corrected triangle winding.

The native payload keeps model/build metadata separate from the generated display mesh so later UI and conversion code can reason about source structure instead of only seeing flattened triangles.

### Deliberate first-version limits

The following are **not yet complete** and must not be advertised as preserved until implemented and fixture-tested:

- base-material/color assignments;
- Texture2D resources and UV/property groups;
- production extension metadata;
- beam lattice;
- volumetric/implicit extensions;
- full extension round-trip export.

### Validation gates

Current implementation gates are intentionally separate:

1. pinned lib3mf Android SDK builds as shared `arm64-v8a` libraries;
2. the real BrepSight 3MF importer compiles and links against that SDK in Android NDK CI;
3. the APK must package both `cad_engine.so` and `lib3mf.so` and advertise 3MF only when the provider is actually staged;
4. representative clean-room fixtures must be opened on Android before 3MF is declared complete.

This prevents build-system success from being mistaken for runtime-format fidelity.

## 5. CAE / simulation

BrepSight should treat CAE as a separate data model, not flatten every result into a colored STL.

### First wave

| Format/family | Target data |
|---|---|
| VTK legacy / VTU / VTP | unstructured/poly data, point/cell fields |
| PVD | time-series dataset collection |
| Gmsh MSH | nodes/elements/physical groups |
| NASTRAN BDF | model/deck geometry and sets where practical |
| Abaqus INP | mesh, sets and basic model metadata |
| CalculiX FRD | result fields and deformed shape |

### Later / optional heavy providers

- CGNS
- Exodus II / SEACAS
- OpenFOAM case/result data
- MED
- additional solver-specific result readers

### Unified result model

Every CAE reader should normalize to:

- mesh nodes/elements;
- element type;
- named sets;
- scalar/vector/tensor result arrays;
- association: node, element, face or integration point where representable;
- unit metadata;
- load case / step / time;
- deformation vector;
- source diagnostics.

The viewer layer can then provide one consistent contour legend, min/max, probe, deformed-shape and time-step UI across solvers.

## 6. SOLIDWORKS and proprietary formats

### Exchange formats: first priority

SOLIDWORKS officially imports/exports STEP, IGES, Parasolid, STL and other exchange formats. BrepSight should therefore make STEP AP242 the recommended high-fidelity route for normal part/assembly viewing.

### Native documents

| Format | Policy |
|---|---|
| `.SLDPRT` | Bridge-only until a redistributable licensed reader exists. |
| `.SLDASM` | Bridge-only until a redistributable licensed reader exists. |
| `.SLDDRW` | Bridge-only; drawing support is a separate 2D/document problem. |
| `.CWR` | Bridge/conversion only. This is the SOLIDWORKS Simulation result database, not a documented open interchange format. |

BrepSight must never market these as native-open formats merely because commercial viewers can read them.

A future `brepsight-convert` desktop helper can optionally use a user's locally installed/licensed CAD application or commercial SDK to convert native proprietary documents into STEP/glTF/VTK-style neutral data without changing the mobile core license.

## 7. Capability reporting

Opening a file should return a structured report rather than a boolean:

```text
provider: occt.step
status: success | partial | failed
sourceFormat: STEP AP242
geometry: exact-brep
hierarchy: yes
colors: yes
materials: partial
pmi: partial
animation: no
results: no
warnings:
  - unsupported presentation item ...
```

This report drives badges in the Flutter UI and prevents silent data loss.

## 8. Dependency/license policy

- BrepSight original code: Apache-2.0.
- Open CASCADE: keep its upstream LGPL-2.1 + exception terms and required notices.
- lib3mf: keep its upstream 2-clause BSD notice; the Android provider is optional and uses shared libraries.
- Assimp candidate: 3-clause BSD-style license.
- FreeCAD code is not copied into the Apache core unless a specific reuse is reviewed for LGPL compliance; FCStd support should preferably be an independent parser based on the documented file structure.
- Blender application code is not linked into the Apache core.
- Commercial translators are optional providers and must never be required for the open core build.

## References used to establish the scope

- Open CASCADE Data Exchange and DE Wrapper documentation.
- FreeCAD FCStd format documentation and FreeCAD license documentation.
- Blender import/export and licensing documentation.
- Assimp supported-format and Android documentation.
- 3MF Core Specification and lib3mf documentation/source.
- SOLIDWORKS 2026 import/export and Simulation result database documentation.
