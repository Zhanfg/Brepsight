# Merge / split / composition workflow

## Goal

Make common emergency engineering edits practical from a phone: combine several models into one deliverable, separate parts from a combined model, reorganize an assembly, and export only the needed pieces.

This is not one operation. BrepSight must distinguish semantic assembly operations from destructive geometric booleans.

## Merge modes

### 1. Assembly merge

```text
part_a.step + part_b.step + part_c.step
              |
              v
        one document tree
```

Preserve original parts, names, transforms, materials and provenance. No geometry is fused.

Use cases:
- send one assembly file instead of several attachments;
- quickly combine supplier/customer parts;
- create a temporary review assembly on a phone.

### 2. Scene / mesh merge

Combine multiple mesh objects into one polygonal object while preserving available material groups and UVs where the output format allows them.

```text
body.obj + screws.obj -> combined.obj
```

This is topology composition, not a solid boolean union. The output may still contain disconnected shells.

### 3. Boolean union

For valid solid/exact geometry, create a true fused solid when supported.

```text
solid A + solid B -> fused solid C
```

Must report failures such as non-intersection, invalid solids, tolerance problems or unsupported source representation.

### 4. Package merge

Create a multi-object output container such as 3MF or glTF/GLB without geometrically modifying parts. This is often the safest format-handoff mode.

## Split modes

### Connected components

Split a mesh into disconnected islands/components.

Useful for:
- STL files containing several printable parts;
- scan output with accidental floating objects;
- combined OBJ assets.

### Material split

Create one object/document part per material assignment.

### Layer split

Split by CAD/drawing/model layer when the source preserves layers.

### Assembly-node split

Extract selected child nodes/parts from STEP/XCAF, FCStd, 3DM, glTF or other hierarchical documents where supported.

### Solid/shell split

For exact CAD, separate multiple solids or shells stored in one part/body/document.

### Selection split

User selects faces/objects in the viewer and chooses **Separate selection**. The operation must leave both the extracted result and remainder valid when the source representation permits it.

## Mobile UI

For a user who is outside the office, the default flow should be short:

```text
Open model
   |
   +--> More > Separate
   |      - By parts
   |      - Connected pieces
   |      - Material
   |      - Layer
   |      - Selected geometry
   |
   +--> More > Combine
          - Keep as assembly      (recommended)
          - Combine mesh objects
          - Boolean union
```

After an operation:

```text
Separated into 7 parts

[Select all] [Rename] [Export]

Housing          42.1 MB
Cover            11.8 MB
Bracket L         3.2 MB
Bracket R         3.2 MB
...
```

## Multi-file intake

The Android file picker should permit selecting several supported files at once.

```text
Select files
  -> importer probe each file
  -> open as temporary documents
  -> normalize units/transforms
  -> composition preview
  -> commit as new EngineeringDocument
```

Do not silently rescale conflicting units. Show a unit-normalization screen when needed.

Example:

```text
part_a.step     mm
part_b.obj      unitless
part_c.3dm      mm

OBJ has no reliable source unit.
Interpret as: [mm] [cm] [m] [inch]
```

## Placement / alignment

Combining files is only useful if placement is manageable.

Initial capabilities:
- preserve source transforms;
- move/rotate/scale;
- align centers;
- align bounding-box faces;
- snap selected points;
- match axes;
- numeric transform entry.

Later:
- planar face alignment;
- cylinder-axis alignment;
- hole/shaft concentric alignment;
- three-point alignment for scans.

## Non-destructive transactions

Every merge/split operation creates a new document transaction.

```text
source documents
      |
      v
 temporary result
      |
 validate
   /      \
 fail     success
 discard   commit
```

The source documents remain recoverable.

## Data preservation report

Composition operations must use the existing capability-report system.

Example: merging two textured OBJ objects into STL:

```text
Geometry             preserved
Disconnected parts   preserved visually
Quad topology        lost / triangulated
UV                    lost
Textures              lost
Materials             lost
Units                 depends on normalization
```

For 3MF/glTF containers, more of these semantics can remain intact.

## Command-line integration

Canonical commands:

```text
merge @a @b --mode assembly
merge @a @b --mode mesh
union @a @b
split @sel connected
split @sel material
split @sel layer
split @assembly children
extract @assembly/gearbox/shaft
explode @assembly
```

`JOIN` should remain a lower-level/topology-oriented command and must not ambiguously mean boolean union.

## Background execution

Large merge/split jobs use the common ModelTask host. Examples:
- boolean fusion of large B-Rep assemblies;
- splitting a multi-million-face scan by components;
- writing a large 3MF/GLB package.

The operation can continue while the application is backgrounded and should report read/analyze/compose/validate/write stages through the Android foreground notification.

## Acceptance path

1. Multi-select three STL/OBJ files on Android.
2. Create a combined assembly/scene without losing original objects.
3. Export to a multi-object format and reopen it.
4. Split a multi-shell STL by connected component.
5. Export individual pieces.
6. Open a representative multi-solid STEP and extract one solid/assembly node without flattening the source document.
7. Loss and unit-normalization reports are visible before destructive conversion/export.
