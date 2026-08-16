# Feature matrix

Legend: ✅ implemented, ◐ scaffold/partial, ○ planned, △ experimental/bridge, — not started.

| Area | Current | Target |
|---|---:|---:|
| Flutter Material 3 shell | ✅ | ✅ |
| System CJK font fallback | ✅ | ✅ |
| Android file picker | ✅ | ✅ |
| Native Android Surface | ✅ | ✅ |
| Native EGL / GLES renderer | ✅ proof | render coordinator |
| Runtime provider routing | ◐ STL / OBJ / STEP / 3MF paths | ✅ |
| Neutral engineering document model | ◐ provider payload + display mesh | ✅ |
| Import diagnostics / capability reporting | ◐ summary metadata | ✅ |
| Orbit / pan / zoom | ✅ proof | ✅ |
| Fit all | ◐ command path | ✅ |
| Perspective / orthographic | ◐ | ✅ |
| Shaded / edges / wireframe | ◐ | ✅ |

## CAD / B-Rep

| Capability | Current | Target |
|---|---:|---:|
| STL | ✅ native mesh importer | ✅ |
| OBJ | ✅ native mesh importer | ✅ |
| STEP / STP | ◐ OCCT/XCAF provider wired; Android provider smoke pending | ✅ |
| STEPZ | — | ✅ |
| IGES / IGS | — | ✅ |
| BREP / XBF | — | ✅ |
| glTF / GLB / VRML | — | ✅ |
| PLY read | — | ✅ via mesh provider |
| Assembly tree | ◐ provider-neutral model | ✅ |
| Names / colors / layers | ◐ XCAF payload path | ✅ |
| STEP AP242 PMI where available | — | ✅ |
| Bounding box / dimensions | ◐ mesh bounds | ✅ |
| Surface area / volume | ◐ mesh diagnostics | ✅ |
| Distance / angle / radius | — | ✅ |
| Section / clipping plane | — | ✅ |
| Topology inspection | ◐ mesh diagnostics | ✅ |

## Additive / 3MF

| Capability | Current | Target |
|---|---:|---:|
| lib3mf Android arm64 SDK | ✅ CI-built and packaged | ✅ |
| Real 3MF importer Android compile/link smoke | ✅ | ✅ |
| Runtime `.3mf` provider routing | ◐ branch-integrated; APK validation pending | ✅ |
| Model unit preservation | ✅ payload; display normalized to mm | ✅ |
| Build items / transforms | ✅ payload + display transform | ✅ |
| Components hierarchy | ✅ recursive core support | ✅ |
| Mirrored transforms / winding | ✅ handled | ✅ |
| Cycle / depth / expansion guards | ✅ | ✅ |
| Base colors / materials | — | ✅ |
| Texture2D / UV | — | ✅ |
| Production / beam lattice extensions | — | ○ |
| Actual Android file-open fixture test | — | ✅ before support is declared complete |

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
| STL / OBJ | ✅ | ✅ |
| PLY / glTF | — | ✅ |
| FBX | — | ✅ via mesh provider |
| Collada DAE | — | ✅ |
| 3DS / OFF | — | ✅ |
| 3MF Core mesh/components | ◐ Android provider validated | ✅ |
| Materials / textures | — | ✅ |
| Scene hierarchy / transforms | ◐ 3MF path only | ✅ |
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
| Mobile deterministic command console | ✅ | ✅ |
| Recent / favorites | — | ✅ |
| Thumbnail cache | — | ✅ |
| File properties / units | ◐ provider metadata | ✅ |
| Import warnings and partial-support badges | ◐ build capability UI | ✅ |
| Large-file progress / cancellation | — | ✅ |
| Mesh diagnostics | ✅ basic | ✅ |
| Screenshot / share | — | ✅ |
| Read-only safe mode | ◐ importer guards | ✅ |
