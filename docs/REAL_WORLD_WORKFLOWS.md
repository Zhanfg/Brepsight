# Real-world mobile workflows

BrepSight is not only a file viewer. Its product model is built around what people actually do with engineering and 3D data on a phone: **capture, open, inspect, fix, convert, and hand off**.

## 1. Capture: real object -> digital model

### Phone depth / AR capture

Target Android capture path:

- ARCore Depth when supported;
- ARCore Raw Depth + confidence image for reconstruction-oriented capture;
- hardware depth / ToF data when the device and ARCore expose it;
- RGB frames + camera pose for photogrammetry-oriented pipelines;
- IMU/camera pose metadata where useful.

Normalized capture outputs:

- point cloud;
- depth frames;
- camera poses;
- reconstructed triangle mesh;
- texture atlas/material images;
- scale/confidence metadata.

Initial export targets:

- PLY point cloud;
- OBJ + textures;
- glTF/GLB;
- STL for geometry-only printing;
- 3MF for print-oriented output with units and richer metadata.

### External scanners

The same capture workspace should import common scanner outputs such as E57, LAS/LAZ, PLY, PCD, XYZ/PTS/PTX and vendor-converted neutral files. BrepSight should not require its own camera pipeline when the user already has scan data.

### Reverse engineering boundary

A scanned triangle mesh is **not** automatically equivalent to an exact parametric CAD model.

BrepSight may later offer assisted reverse-engineering operations such as:

- plane/cylinder/sphere detection;
- section extraction;
- curve fitting;
- surface fitting;
- mesh-to-BRep approximation;
- dimension suggestions;
- alignment to principal axes/reference planes.

Any derived STEP/BRep export must clearly report whether geometry is exact, fitted, faceted, or approximate. The app must never silently present a triangulated scan as recovered original CAD history.

## 2. Convert: the phone as a format transit station

The conversion workspace imports once into a neutral document and exports through a format-capability-aware writer.

Typical phone workflows:

- STEP -> STL/3MF for printing;
- Rhino 3DM -> glTF/GLB for quick sharing;
- OBJ/FBX -> GLB for compact preview;
- PLY/E57 point cloud -> filtered/downsampled PLY;
- DXF -> SVG/PDF-style preview or geometry exchange where supported;
- FCStd stored geometry -> STEP/GLB where the recovered document capabilities permit it;
- CAE results -> VTK/VTU-compatible neutral result data;
- scan mesh -> STL/3MF after cleanup.

### Loss-aware conversion

Every conversion produces a report such as:

```text
source: STEP AP242
source capabilities: exact B-Rep, assembly tree, colors, names
output: STL
preserved: triangle geometry
lost: assembly semantics, exact surfaces, names, colors, PMI
status: completed_with_loss
```

Conversions with major semantic loss require explicit user acknowledgement in the UI.

### Export tiers

**P0 writers**

- STL
- OBJ
- glTF/GLB
- PLY
- 3MF

**P1 writers**

- STEP when source data contains valid exact/fitted B-Rep suitable for STEP export
- DXF for supported drawing/curve subsets
- VTK/VTU for normalized CAE data
- point-cloud text/binary interchange

Proprietary native writers remain optional licensed providers or desktop bridges.

## 3. Inspect and fix

The phone is often used for rapid verification before printing, machining, sharing, or approving a file.

Common operations:

- units and scale check;
- bounding box/dimensions;
- orientation and origin;
- part/assembly tree;
- distance/angle/radius/area/volume;
- clipping/section;
- triangle count and mesh density;
- normals;
- open boundaries;
- non-manifold edges;
- duplicate/degenerate triangles;
- watertightness;
- mesh simplification;
- safe mesh repair;
- point-cloud crop/downsample;
- coordinate-system metadata;
- CAE probe/min/max/field inspection;
- print build-volume check.

Repairs must be undoable within the active document session and recorded in an operation report.

## 4. Handoff

BrepSight should integrate with normal Android file behavior rather than inventing a closed library.

Targets:

- Android Open with / Storage Access Framework;
- Android Share sheet input and output;
- export to Downloads/user-selected folder;
- send converted files to slicers, messaging apps, email, cloud drives, or other CAD apps;
- generate thumbnail/preview image;
- optionally package model + textures + conversion report into one archive;
- recent files without taking ownership of the original document.

No automatic cloud upload is required for core functionality.

## 5. Product rule

A feature belongs in BrepSight when it answers a real mobile question such as:

- "What is this file?"
- "Can I open it?"
- "Is the scale correct?"
- "Can I print this?"
- "Can I inspect this result away from my workstation?"
- "Can I turn this into a format the next app understands?"
- "Can I scan this object and get a usable mesh?"
- "What information will I lose if I convert it?"

Desktop-class editing, parametric history authoring, full simulation solving and machine control are not prerequisites for a useful mobile engineering tool.
