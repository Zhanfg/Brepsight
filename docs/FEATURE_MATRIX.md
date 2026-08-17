# Feature matrix

Legend: ✅ implemented/validated, ◐ scaffold/partial, ○ planned, △ experimental/bridge, — not started.

| Area | Current | Target |
|---|---:|---:|
| Flutter Material 3 shell | ✅ | ✅ |
| System CJK font fallback | ✅ | ✅ |
| Android file picker | ✅ | ✅ |
| Native Android Surface | ✅ | ✅ |
| Native EGL / GLES renderer | ✅ proof | render coordinator |
| Runtime provider routing | ◐ STL / OBJ / STEP / 3MF / BREP / FCStd saved geometry | ✅ |
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
| STEP / STP | ✅ OCCT/XCAF Android provider validated | ✅ |
| STEPZ | — | ✅ |
| IGES / IGS | — | ✅ |
| BREP / BRP | ✅ OCCT exact provider + real semantic smoke | ✅ |
| XBF | — | ✅ |
| glTF / GLB / VRML | — | ✅ |
| PLY read | — | ✅ via mesh provider |
| Assembly tree | ◐ STEP/XCAF counting + provider-neutral model | ✅ |
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
| Runtime `.3mf` provider routing | ✅ Android APK validated | ✅ |
| Model unit preservation | ✅ payload; display normalized to mm | ✅ |
| Build items / transforms | ✅ payload + display transform | ✅ |
| Components hierarchy | ✅ recursive core support | ✅ |
| Mirrored transforms / winding | ✅ handled + semantic fixture | ✅ |
| Cycle / depth / expansion guards | ✅ | ✅ |
| Base colors / materials | — | ✅ |
| Texture2D / UV | — | ✅ |
| Production / beam lattice extensions | — | ○ |
| Actual Android file-open fixture test | — | ✅ before full-fidelity support is declared complete |

## FreeCAD

Current support is deliberately a **read-only saved-geometry subset**, not a FreeCAD runtime and not a parametric document host.

| Capability | Current | Target |
|---|---:|---:|
| FCStd container detection / safe preprocessing | ✅ | ✅ |
| ZIP count / size / compression / path guards | ✅ JVM fixtures | ✅ |
| Safe `Document.xml` parsing | ✅ DTD/entities/network blocked | ✅ |
| Safe `GuiDocument.xml` parsing | ✅ DTD/entities/network blocked | ✅ |
| Stored BREP / BRP geometry extraction | ✅ referenced shapes only | ✅ |
| Direct BREP exact payload | ✅ OCCT + real semantic smoke | ✅ |
| Multiple saved-shape aggregation | ✅ | ✅ |
| Object names / type / label / object count | ◐ Manifest V2 payload | ✅ |
| True object tree reconstruction | ◐ explicit `Group` PropertyLinkList subset | ✅ |
| Placements / transforms from FreeCAD document metadata | ◐ group-parent + child Placement composed | ✅ |
| `GuiDocument.xml` colors / visibility | ◐ saved-BREP object Visibility + ShapeColor applied through GLES draw ranges; richer presentation pending | ✅ |
| Interactive object visibility | ◐ Flutter object tree + local/effective Group-inherited visibility; no FCStd write-back | ✅ |
| Visible bounds / default Fit All | ◐ hidden saved-BREP ranges excluded and recomputed after live visibility changes | ✅ |
| Unsupported-object partial diagnostics | ◐ unreadable saved shapes skipped; richer diagnostics pending | ✅ |
| Embedded thumbnail extraction | — | ✅ |
| Parametric recompute | deliberately disabled | not a viewer goal |
| Embedded Python / macro / pickle execution | deliberately prohibited | deliberately prohibited |

## Mesh / Blender / DCC ecosystem

| Capability | Current | Target |
|---|---:|---:|
| STL / OBJ | ✅ | ✅ |
| PLY / glTF | — | ✅ |
| FBX | — | ✅ via mesh provider |
| Collada DAE | — | ✅ |
| 3DS / OFF | — | ✅ |
| 3MF Core mesh/components | ✅ Android provider validated | ✅ |
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
| Read-only safe mode | ◐ FCStd hardened container boundary + importer guards | ✅ |
