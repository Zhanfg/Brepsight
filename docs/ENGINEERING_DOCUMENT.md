# Engineering document contract

`EngineeringDocument` is the semantic boundary between file-format providers and the BrepSight UI/tools. It is intentionally **not** a lowest-common-denominator triangle mesh.

## Representations

A document may contain one or more representations at the same time:

- `exactGeometry` — B-Rep/NURBS/curves/surfaces and topology;
- `mesh` — polygonal render/manufacturing geometry;
- `drawing` — layers, blocks, curves, dimensions and text;
- `pointCloud` — points plus color/intensity/confidence attributes;
- `simulation` — nodes/elements and result fields;
- `toolpath` — machine/tool movements treated strictly as inspectable data;
- `bim` — object/property/spatial semantics;
- `volumetric` — voxel/field data.

Importers must retain the richest representation they can recover. Tessellating exact CAD for rendering does not erase the exact representation.

## Flutter/native boundary

Large engineering data stays native-side. Flutter receives only:

- an opaque `nativeHandle`;
- lightweight metadata;
- object/tree summaries requested for visible UI;
- inspection/query results.

Large vertex arrays, point clouds, CAE fields and B-Rep structures must not be copied through MethodChannel for normal viewing.

## Import contract

Every importer implements:

1. `probe()` — content-aware confidence score;
2. `importDocument()` — normalized document creation;
3. provenance — source format and provider identity;
4. explicit capabilities.

File extension is a hint, not authoritative identification.

## Export contract

Every writer provides `ExportAnalysis` before writing. Source capabilities must be classified as:

- `preserved`;
- `degraded`;
- `lost`;
- `notApplicable`.

The conversion UI must surface material losses before export when they change engineering meaning.

Examples:

- STEP -> STL loses exact B-Rep, hierarchy and PMI even when the shape looks identical;
- STEP -> 3MF may preserve units, colors and multiple build items while still losing exact surfaces;
- OBJ -> GLB can preserve mesh/material/texture semantics more faithfully than OBJ -> STL;
- CAE -> mesh-only formats loses result fields and therefore must be reported as a semantic loss.

## Reverse-engineering rule

A scan/reconstructed triangle mesh is **not** parametric CAD. Mesh-to-BRep/STEP output is permitted only after an explicit fitting/reverse-engineering stage. The output provenance must identify it as fitted/approximate and retain tolerance/error metrics where known.

## Toolpath safety

G-code, NC and slicer toolpaths are data for inspection. BrepSight does not automatically execute, stream or transmit machine commands.

## Provider independence

Flutter and product tools must not branch on OCCT/Assimp/openNURBS implementation details. Providers feed this common contract so a provider can be replaced without rewriting viewer, measurement or conversion UI.
