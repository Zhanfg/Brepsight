# Feature matrix

Legend: ✅ implemented, ◐ scaffold/partial, ○ planned, △ experimental/bridge, — not started.

| Area | Current | Target |
|---|---:|---:|
| Flutter Material 3 shell | ✅ | ✅ |
| System CJK font fallback | ✅ | ✅ |
| Android file picker | ✅ | ✅ |
| Native Android Surface | ✅ | ✅ |
| Native EGL / GLES renderer | ✅ proof | render coordinator |
| Importer registry | — | ✅ |
| Neutral engineering document model | — | ✅ |
| Import diagnostics / capability reporting | — | ✅ |
| Orbit / pan / zoom | ✅ proof | ✅ |
| Fit all | ◐ command stub | ✅ |
| Perspective / orthographic | ◐ command stub | ✅ |
| Shaded / edges / wireframe | ◐ command stub | ✅ |

## CAD / B-Rep

| Capability | Current | Target |
|---|---:|---:|
| STL | ◐ load API stub | ✅ |
| STEP / STP / STEPZ | ◐ load API stub | ✅ |
| IGES / IGS | ◐ load API stub | ✅ |
| BREP / XBF | — | ✅ |
| OBJ / glTF / GLB / VRML | — | ✅ |
| PLY read | — | ✅ via mesh provider |
| Assembly tree | — | ✅ |
| Names / colors / layers | — | ✅ |
| STEP AP242 PMI where available | — | ✅ |
| Bounding box / dimensions | — | ✅ |
| Surface area / volume | — | ✅ |
| Distance / angle / radius | — | ✅ |
| Section / clipping plane | — | ✅ |
| Topology inspection | — | ✅ |

## FreeCAD

| Capability | Current | Target |
|---|---:|---:|
| FCStd container detection | — | ✅ |
| Safe Document.xml parsing | — | ✅ |
| Stored BREP geometry extraction | — | ✅ |
| Labels / hierarchy / basic display metadata | — | ✅ |
| Embedded thumbnail extraction | — | ✅ |
| Parametric recompute | — | not a viewer goal |
| Embedded Python/macro execution | — | deliberately prohibited |

## Mesh / Blender / DCC ecosystem

| Capability | Current | Target |
|---|---:|---:|
| OBJ / PLY / STL / glTF | — | ✅ |
| FBX | — | ✅ via mesh provider |
| Collada DAE | — | ✅ |
| 3DS / OFF / 3MF | — | ✅ |
| Materials / textures | — | ✅ |
| Scene hierarchy / transforms | — | ✅ |
| Basic animation metadata | — | ○ |
| USD / USDZ | — | ○ dedicated provider |
| Alembic ABC | — | ○ dedicated provider |
| Native BLEND | — | △ experimental / optional bridge |

## CAE / simulation

| Capability | Current | Target |
|---|---:|---:|
| Node / element mesh model | — | ✅ |
| Scalar result fields | — | ✅ |
| Vector result fields | — | ✅ |
| Tensor result fields | — | ○ |
| Time steps / load cases | — | ✅ |
| Deformed shape | — | ✅ |
| Contour legend / min-max / probe | — | ✅ |
| VTK / VTU / VTP / PVD family | — | ✅ |
| Gmsh MSH | — | ✅ |
| NASTRAN BDF geometry/deck | — | ○ |
| Abaqus INP | — | ○ |
| CalculiX FRD | — | ○ |
| CGNS / Exodus II | — | ○ optional heavy providers |
| OpenFOAM case/results | — | ○ |
| SOLIDWORKS Simulation CWR | — | △ bridge/conversion only |

## Proprietary CAD

| Format | Policy |
|---|---|
| SOLIDWORKS SLDPRT / SLDASM | Do not claim native support without a redistributable licensed provider; prefer STEP AP242 exchange. |
| Parasolid X_T / X_B | Optional provider; base open OCCT does not include the commercial Parasolid translator. |
| CATIA / NX / Creo native formats | Optional licensed provider or documented exchange route. |
| eDrawings native formats | Optional licensed/bridge route only. |

## General viewer services

| Capability | Current | Target |
|---|---:|---:|
| Recent / favorites | — | ✅ |
| Thumbnail cache | — | ✅ |
| File properties / units | — | ✅ |
| Import warnings and partial-support badges | — | ✅ |
| Large-file progress / cancellation | — | ✅ |
| Mesh diagnostics | — | ✅ |
| Screenshot / share | — | ✅ |
| Read-only safe mode | — | ✅ |
