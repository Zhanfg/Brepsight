
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