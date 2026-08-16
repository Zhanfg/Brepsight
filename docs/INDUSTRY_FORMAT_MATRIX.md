# Industry format coverage matrix

BrepSight aims to be a **mobile universal engineering/3D document viewer**. The goal is broad read/inspect coverage across mechanical CAD, drafting, Rhino/NURBS, DCC, additive manufacturing, point clouds, BIM/AEC, CAE and CAM — without pretending every proprietary format can be implemented by the open core.

Status vocabulary:

- **P0 native** — baseline format; should become a first-class offline Android reader.
- **P1 native** — high-value maintained provider after the baseline.
- **P2 native** — useful long-tail provider.
- **Experimental** — unstable/partial reader; UI must disclose limitations.
- **Bridge** — requires licensed SDK, external companion, or desktop conversion.

## A. Neutral / exact CAD geometry

| Family | Extensions | Target | Provider strategy |
|---|---|---|---|
| STEP / AP203 / AP214 / AP242 | `.stp`, `.step`, `.stepz` | P0 native | OCCT / XCAF |
| IGES | `.igs`, `.iges` | P0 native | OCCT |
| Open CASCADE BREP | `.brep`, `.brp` | P0 native | OCCT |
| XCAF binary document | `.xbf` | P1 native | OCCT |
| ACIS SAT/SAB | `.sat`, `.sab` | Bridge | licensed translator or converter |
| Parasolid | `.x_t`, `.x_b`, `.xmt_txt`, `.xmt_bin` | Bridge | licensed translator |
| JT | `.jt` | Bridge/P2 | dedicated reader or licensed provider |
| VDA-FS | `.vda` | P2 | dedicated reader / converter |
| PRC / 3D PDF geometry | `.prc`, `.pdf` | Bridge | dedicated/licensed provider |

## B. AutoCAD / drafting / civil drawing ecosystem

| Format | Extensions | Target | Notes |
|---|---|---|---|
| AutoCAD DXF | `.dxf`, `.dxb`, `.dxfb` | **P0 native** | BrepSight read-only DXF parser for common 2D/3D entities; preserve layers, blocks, colors, line types and units where available. |
| AutoCAD DWG | `.dwg` | **P1 provider** | optional ODA Drawings SDK on Android; do not bundle GPL LibreDWG into the Apache core. |
| Autodesk DWF/DWFx | `.dwf`, `.dwfx` | P2/Bridge | ODA/licensed provider; 2D and 3D presentation semantics differ. |
| MicroStation DGN | `.dgn` | P2/Bridge | dedicated/ODA provider. |
| AutoCAD plot | `.plt`, `.hpgl`, `.hpgl2` | P2 | 2D preview/import path. |
| AutoCAD vector exchange | `.wmf`, `.emf` | P2 | preview/2D import only. |

DXF and DWG must share a normalized drawing model:

- layers;
- blocks/instances;
- line/polyline/spline/arc/circle/ellipse;
- hatches;
- text/dimensions where supported;
- 3DFACE / meshes / polyface;
- solids/surfaces when a provider exposes them;
- layouts/model space;
- units and coordinate system metadata.

## C. Rhino / NURBS ecosystem

`Rhino 8` uses the normal Rhino `.3dm` document format; there is no separate `.rh8` primary model extension.

| Format | Extensions | Target | Provider |
|---|---|---|---|
| Rhino 3DM v1-v8+ | `.3dm` | **P0 native** | McNeel openNURBS |
| Rhino backup | `.3dmbak` | P1 native | openNURBS after safe backup handling |
| Rhino worksession | `.rws` | P2 | reference resolver only; no missing-file guessing |

Preserve when present:

- NURBS curves/surfaces and BReps;
- meshes and saved render meshes;
- SubD metadata/render representation;
- layers and object attributes;
- instance definitions/references;
- materials/render content;
- views/construction planes where useful;
- annotations/dimensions as inspection objects.

openNURBS itself does not provide every geometric operation or general tessellator, so BrepSight should use saved render meshes when available and progressively map exact Rhino geometry into the OCCT/neutral geometry layer.

## D. Major proprietary mechanical CAD applications

These formats matter for recognition, file picking, diagnostics and optional bridge providers even when the open core cannot parse them.

| Ecosystem | Extensions | Target |
|---|---|---|
| SOLIDWORKS | `.sldprt`, `.sldasm`, `.slddrw`, `.cwr` | Bridge |
| Autodesk Inventor | `.ipt`, `.iam`, `.idw`, `.ipn` | Bridge |
| Autodesk Fusion | `.f3d`, `.f3z` | Bridge/converter |
| CATIA V4 | `.model`, `.session`, `.exp`, `.dlv*` | Bridge |
| CATIA V5/V6/3DEXPERIENCE | `.catpart`, `.catproduct`, `.cgr` | Bridge |
| Siemens NX | `.prt` | Bridge |
| PTC Creo / ProE | `.prt`, `.asm`, `.drw` | Bridge; content probing required because extensions are ambiguous |
| Solid Edge | `.par`, `.psm`, `.asm`, `.dft` | Bridge |
| Autodesk Alias | `.wire` | Bridge |
| SketchUp | `.skp` | P2/Bridge |

Recommended interchange route for these systems remains STEP AP242 where exact CAD hierarchy is required and glTF/3MF where a mesh/manufacturing representation is sufficient.

## E. DCC / Blender / visualization scenes

| Format | Extensions | Target | Provider |
|---|---|---|---|
| Wavefront OBJ + MTL | `.obj`, `.mtl` | P0 native | mesh provider |
| glTF 2.0 | `.gltf`, `.glb` | P0 native | OCCT/mesh provider |
| FBX | `.fbx` | P1 native | Assimp first, dedicated provider if fidelity requires |
| COLLADA | `.dae` | P1 native | Assimp |
| 3D Studio | `.3ds` | P1 native | Assimp |
| USD | `.usd`, `.usda`, `.usdc`, `.usdz` | P1 native | dedicated OpenUSD provider |
| Alembic | `.abc` | P1 native | dedicated provider |
| Blender document | `.blend` | Experimental | independent reader or separate GPL/desktop bridge; not a launch fidelity promise |
| LightWave | `.lwo`, `.lws` | P2 | Assimp/dedicated |
| DirectX | `.x` | P2 | Assimp |
| OpenInventor | `.iv` | P2 | mesh/scene provider |
| VRML | `.wrl`, `.vrml` | P1 | OCCT/scene provider |
| X3D | `.x3d`, `.x3dv` | P2 | dedicated parser |
| OFF | `.off` | P1 | simple mesh parser |
| GTS | `.gts` | P2 | simple mesh parser |
| Raw triangles | `.raw` | P2 | simple mesh parser |

## F. 3D printing / additive manufacturing / slicer ecosystem

| Format | Extensions | Target | Notes |
|---|---|---|---|
| STL | `.stl` | **P0 native** | binary + ASCII; unit warning; mesh repair diagnostics |
| 3MF | `.3mf` | **P0 native** | use lib3mf; preserve units/materials/colors/build items and supported extensions |
| AMF | `.amf` | P1 native | ISO/ASTM XML-based additive format |
| OBJ | `.obj` | P0 native | mesh + material path |
| PLY | `.ply` | P1 native | color/scan/mesh use cases |
| G-code | `.gcode`, `.gco`, `.gc`, `.nc` | **P1 native toolpath viewer** | parse moves, extrusion, temperatures, layers and time metadata; never execute machine commands |
| Binary G-code | `.bgcode` | P1 native | dedicated parser when format revision is known |
| CLI layer format | `.cli` | P2 native | additive slice contours |
| SLC | `.slc` | P2 native | slice contours |
| printer/slicer project 3MF | `.3mf` | P1 profile | detect vendor namespaces; preserve unknown metadata instead of deleting it |
| resin slicer formats | `.ctb`, `.cbddlp`, `.photon`, `.pwmo`, etc. | Experimental | vendor/revision-specific preview providers only |

The additive model must distinguish **design geometry** from **sliced/toolpath data**. A G-code or resin slice file is not a CAD solid.

## G. Point cloud / 3D scanning / reverse engineering

| Format | Extensions | Target |
|---|---|---|
| ASTM E57 | `.e57` | P1 native |
| LAS / LAZ | `.las`, `.laz` | P1 native |
| PCD | `.pcd` | P1 native |
| PLY point cloud | `.ply` | P1 native |
| generic points | `.xyz`, `.pts`, `.ptx`, `.asc`, `.csv`, `.txt` | P1 native with schema detection |
| Autodesk ReCap | `.rcp`, `.rcs` | Bridge |
| Leica/PTG/PTX-like vendor sets | vendor-specific | P2/Bridge |

Point-cloud viewers need streaming/chunking, point-size controls, color/intensity modes, clipping and large-file LOD rather than mesh-only rendering assumptions.

## H. BIM / AEC

| Format | Extensions | Target |
|---|---|---|
| IFC | `.ifc`, `.ifczip`, `.ifcxml` | P1 native/optional provider |
| Revit | `.rvt`, `.rfa`, `.rte` | Bridge |
| DGN | `.dgn` | P2/Bridge |
| DWG/DXF | `.dwg`, `.dxf` | shared drawing providers |
| gbXML | `.xml`, `.gbxml` | P2 |
| BCF | `.bcf`, `.bcfzip`, `.bcfxml` | P2 collaboration metadata |

BIM imports must preserve object identity, hierarchy, properties and spatial structure; triangle-only IFC import does not count as full BIM support.

## I. CAE / simulation / scientific mesh

| Family | Extensions | Target |
|---|---|---|
| VTK legacy | `.vtk` | P1 native |
| VTK XML | `.vtu`, `.vtp`, `.vts`, `.vtr`, `.vti`, `.pvd` | P1 native |
| Gmsh | `.msh` | P1 native |
| CalculiX | `.frd`, `.inp` | P1 native |
| Abaqus | `.inp` | P1 native |
| Abaqus results | `.odb` | Bridge |
| NASTRAN | `.bdf`, `.nas`, `.dat` | P1 native |
| NASTRAN results | `.op2`, `.f06` | P2 |
| CGNS | `.cgns` | P2 |
| Exodus II | `.e`, `.exo`, `.ex2` | P2 |
| MED | `.med` | P2 |
| OpenFOAM | case directories | P2 provider |
| ANSYS model | `.cdb` | P2 |
| ANSYS results | `.rst`, `.rth` | Bridge/experimental |
| LS-DYNA | `.k`, `.key` | P2 |
| LS-DYNA results | `d3plot` family | P2/experimental |
| UNV/I-DEAS | `.unv` | P2 |

## J. CAM / CNC / manufacturing toolpaths

| Format | Extensions | Target |
|---|---|---|
| G-code / RS-274 family | `.gcode`, `.nc`, `.tap`, `.cnc`, `.ngc` | P1 native viewer |
| APT / CL data | `.apt`, `.cl`, `.cld` | P2 |
| STEP-NC | `.stpnc`, `.p21` and detected STEP-NC documents | P2 |

The mobile app is an inspector, not a machine controller. BrepSight must never automatically transmit or execute a toolpath.

## K. Volumetric / voxel / implicit assets

| Format | Extensions | Target |
|---|---|---|
| OpenVDB | `.vdb` | P2 |
| NanoVDB container/data | provider-specific | P2 |
| 3MF Volumetric | `.3mf` | P2 via lib3mf/supporting provider |

## L. 2D/vector documents useful in design workflows

These are secondary preview/import domains, not the main 3D geometry core:

- PDF;
- SVG/SVGZ;
- AI/EPS where a safe vector path is available;
- raster references: PNG/JPEG/TIFF/WebP;
- technical drawing layouts embedded in supported CAD/BIM documents.

## Provider/license rules

1. BrepSight original code remains Apache-2.0.
2. A format being listed does **not** mean it is currently loadable.
3. Permissive/LGPL-with-compatible-exception libraries can be integrated only after license review and notices.
4. GPL readers such as LibreDWG are not linked into the default Apache APK; they may only be used through a clearly separated GPL companion/conversion workflow.
5. Commercial SDKs such as ODA/other licensed CAD translators are optional providers and must never be required for the open build.
6. Proprietary formats are not reverse-engineered merely to inflate a format-count claim; prefer documented interchange or legal SDK routes.
7. Every importer reports preserved/lost capabilities: exact geometry, mesh, hierarchy, layers, materials, PMI/annotations, units, animation, BIM properties, result fields and toolpaths.

## Product baseline

A useful first broad release should not wait for every bridge format. The baseline should be:

**STEP, IGES, BREP, STL, 3MF, OBJ, glTF/GLB, DXF, Rhino 3DM, PLY, VRML, FBX/DAE, FCStd, VTK/VTU, Gmsh and G-code.**

DWG follows through an optional provider, while proprietary native CAD documents remain clearly marked as bridge formats.