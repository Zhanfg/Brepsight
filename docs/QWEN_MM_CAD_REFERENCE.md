# Qwen-MM CAD reference

Status: research note for `feature/text-to-cad`.

## Why it matters

`QwenLM/Qwen-MM-Plugins` is relevant to BrepSight for more than visual input. Its FreeCAD capability turns a running CAD application into a set of agent-callable engineering tools.

The important pattern is:

```text
inspect state -> structured CAD operation -> recompute -> inspect result -> render/measure -> revise
```

Qwen-MM's FreeCAD skill covers parametric parts and assemblies, object/property editing, technical drawings, STEP/STL/OBJ/DXF exchange, and FEM/CalculiX workflows.

## Architecture lesson

Qwen-MM uses a thin MCP client talking to a running FreeCAD instance. The agent does not need to manipulate the GUI directly. It can call operations such as:

- list/create documents;
- inspect objects;
- create `Part::*`, `Draft::*`, `PartDesign::*` and `Fem::*` objects;
- edit properties and placements;
- verify a modified object by reading it back;
- render a view for visual checking;
- use reusable parts from a library;
- export engineering formats;
- run long CAD computations separately from document/UI mutations.

BrepSight should borrow this stateful tool model, not bundle desktop FreeCAD into the Android APK.

## BrepSight adaptation

```text
text / voice / image
        |
        v
 intent + evidence
        |
        v
      CAD-IR
        |
        v
  CadToolSession
    /       \
local OCCT   optional external CAD provider
    \       /
        v
EngineeringDocument
        |
geometry + visual validation
        |
critique / revision
```

### Local Android provider

The default phone path should implement typed operations directly with BrepSight/OCCT, for example:

- document inspection;
- box/cylinder and sketch primitives;
- extrude/pocket/hole;
- fillet/chamfer/pattern;
- boolean operations;
- move/rotate/mirror;
- property changes;
- measurements and validation;
- canonical view rendering;
- export.

Each mutation returns stable document/object/feature references that can be inspected again.

### Optional FreeCAD provider

A later desktop or local-network companion can expose a broader FreeCAD-backed provider for advanced PartDesign, Assembly, Drawing or FEM tasks. It can follow or interoperate with the Qwen-MM-style tool protocol while remaining optional.

## Inspect -> mutate -> verify

Every agent CAD edit should follow this discipline:

1. inspect current document state;
2. resolve stable references;
3. apply typed operations;
4. recompute in a temporary transaction;
5. read changed objects and measurements back;
6. render a canonical view when useful;
7. compare against requested constraints and visual evidence;
8. commit or revise.

This is a stronger foundation than assuming that a generated CAD command succeeded.

## Reusable component library

Qwen-MM prefers using known parts from a library when possible. BrepSight should later support reusable standard components such as fasteners, bearings, profiles and user-defined parts so Text-to-CAD can assemble known components instead of rebuilding everything from primitives.

## FEM convergence

The same tool model can eventually cover simulation:

```text
geometry -> material -> mesh -> constraints/loads -> solver -> SimulationDocument -> result inspection
```

This fits BrepSight's planned CAE document model.

## Relationship to the visual bridge

Qwen-MM provides two useful ideas that remain separate:

- CAD tools control and inspect the engineering model;
- multimodal tools provide reference-image and render evidence.

They converge in the validation loop, while exact geometry remains authoritative for dimensions and topology.

## Research milestones

- Q0: record the Qwen-MM CAD pattern.
- Q1: define `CadToolProvider` and `CadToolSession`.
- Q2: map the mobile command engine and CAD-IR to the same tool protocol.
- Q3: implement a small local OCCT tool provider.
- Q4: complete text -> CAD-IR -> tools -> inspect -> validate -> revise on Android.
- Q5: prototype an optional FreeCAD/Qwen-MM-style external provider.
