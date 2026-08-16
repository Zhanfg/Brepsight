# Format support strategy

BrepSight targets broad **read/inspect** coverage rather than pretending every format is equally supported. Each format belongs to one of four support classes:

- **First-class native** — intended to open offline on Android with a maintained in-process provider.
- **Planned native** — technically suitable for an open provider, but not part of the first importer milestones.
- **Experimental** — format is unstable, poorly documented, or available only through a weak reader.
- **Bridge only** — no legally redistributable, maintainable open reader is available; use an optional licensed provider or conversion workflow.

The UI must show the class and any lost capabilities instead of reporting a generic success.

## 1. CAD / exact geometry

### First-class native

| Format | Extensions | Initial provider | Notes |
|---|---|---|---|
| STEP | `.stp`, `.step`, `.stepz` | Open CASCADE | Prefer XCAF path for assembly/name/color/layer metadata and AP242 where available. |
| IGES | `.igs`, `.iges` | Open CASCADE | Exact surface/B-Rep import. |
| Open CASCADE BREP | `.brep`, `.brp` | Open CASCADE | Useful for FreeCAD stored shapes and engineering interchange. |
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
| 3MF | Mesh/additive provider; preserve units/materials when possible. |
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

Target behavior:

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
- 3MF
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

## 4. CAE / simulation

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

## 5. SOLIDWORKS and proprietary formats

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

## 6. Capability reporting

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

## 7. Dependency/license policy

- BrepSight original code: Apache-2.0.
- Open CASCADE: keep its upstream LGPL-2.1 + exception terms and required notices.
- Assimp candidate: 3-clause BSD-style license.
- FreeCAD code is not copied into the Apache core unless a specific reuse is reviewed for LGPL compliance; FCStd support should preferably be an independent parser based on the documented file structure.
- Blender application code is not linked into the Apache core.
- Commercial translators are optional providers and must never be required for the open core build.

## References used to establish the scope

- Open CASCADE Data Exchange and DE Wrapper documentation.
- FreeCAD FCStd format documentation and FreeCAD license documentation.
- Blender import/export and licensing documentation.
- Assimp supported-format and Android documentation.
- SOLIDWORKS 2026 import/export and Simulation result database documentation.
