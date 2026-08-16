# Natural-Language CAD Agent

Status: research / future branch only (`feature/text-to-cad`).

## Scope

The feature is broader than text-to-CAD generation. BrepSight should let a user use natural language or voice to **create, inspect, select, modify, repair, compose, convert and validate an existing engineering model**.

The working name `text-to-cad` remains the prototype branch name, but the product concept is a **Natural-Language CAD Agent**.

## Intent families

```text
CREATE    create a new model or feature
EDIT      modify an existing model/feature/parameter
QUERY     ask dimensions, properties, topology or material questions
SELECT    resolve objects/features from natural-language references
TRANSFORM move / rotate / scale / mirror / align
REPAIR    heal CAD, repair mesh, retopologize, unwrap, rebake
COMPOSE   merge, split, extract, explode, assemble
CONVERT   export/convert through the loss-aware writer pipeline
VALIDATE  exact + visual validation
SIMULATE  future CAE/FEM setup and result queries
```

## Examples

### Create

> Create a 60 x 40 x 8 mm plate, R4 outer corners, with four M4 clearance holes 5 mm from the edges.

### Modify an existing model

> Make these two holes 6 mm instead.

> Increase the plate thickness to 10 mm but keep the top face in the same world position.

> Move the motor mount 12 mm toward the rear and keep the shaft axes concentric.

> Remove the three ribs on the left side but preserve the outer wall.

> Split this imported STL into separate connected parts, then merge only the two selected pieces.

### Query / inspect

> What is the minimum wall thickness around this pocket?

> Which holes are not symmetric about the X axis?

> How far is this mounting face from the datum plane?

## Reference resolution

Natural-language editing is unsafe unless references are stable and explicit. The agent must never rely only on screen coordinates or vague ordinal descriptions.

Reference sources, in priority order:

1. explicit user selection (`@sel`);
2. stable object/feature IDs from `CadToolSession`;
3. named features / assembly nodes / layers;
4. geometric predicates (e.g. circular holes on top face, radius near 3 mm);
5. visual regions only as candidate evidence, followed by geometry binding.

When more than one valid target remains, the UI should ask the user to tap or choose candidates.

## Edit transaction model

```text
Natural request
    |
    v
Intent + reference resolution
    |
    v
CadEditPlan
    |
    +--> unresolved/ambiguous? -> ask for binding
    |
    v
Temporary document transaction
    |
    v
Apply typed CadToolInvocation steps
    |
    v
Recompute
    |
    v
Exact validation + optional visual validation
    |
    +--> fail -> critique/revise/discard
    |
    v
Show change summary / preview
    |
    v
Commit
```

The current visible document must remain untouched until commit.

## Change summary

Before committing a non-trivial edit, BrepSight should be able to show a compact semantic diff:

```text
Requested
  Increase selected hole diameter to 6 mm

Targets
  Hole_04
  Hole_05

Changes
  Diameter: 4.5 mm -> 6.0 mm

Preserved
  Hole centers
  Through depth
  Plate thickness
  Assembly placement

Validation
  Solid valid             yes
  Minimum wall            2.8 mm
  Interference introduced no

[Apply] [Revise] [Cancel]
```

## CAD-IR and tool convergence

Natural language, the mobile command line and future GUI automation compile to the same typed operation layer.

```text
"move the bracket up 10 mm"
          |
          v
CadEditPlan
          |
          v
CadToolInvocation(tool: move, dz: 10 mm)
```

No agent path should have a privileged hidden geometry API that cannot be replayed by the operation history.

## Qwen-MM lessons

`QwenLM/Qwen-MM-Plugins` is useful in two independent ways:

1. multimodal evidence can feed a text-oriented reasoner;
2. its FreeCAD capability demonstrates a stateful CAD tool loop: inspect state -> structured operation -> recompute -> inspect/visualize -> revise.

BrepSight should implement the same discipline with typed mobile-native `CadToolSession` operations. An optional desktop/network FreeCAD provider can be added later.

## Existing-model editing requirements

A production-quality agent must support:

- parameter edits without unnecessary topology replacement;
- feature insertion/removal/reorder where the provider supports history;
- transforms and alignment constraints;
- booleans and feature edits;
- mesh operations such as repair/retopology/UV;
- assembly-node operations;
- non-destructive temporary transactions;
- undo/redo and replay;
- stable provenance for agent-created changes;
- a human-readable semantic diff;
- exact geometry validation after every mutating plan.

## Failure behavior

The agent must not silently reinterpret a failed edit as a different operation. Examples:

- if a requested fillet radius is geometrically impossible, report the failing edges/radius;
- if topology changed and an old feature reference no longer exists, re-resolve or ask;
- if a mesh cannot preserve UVs through an operation, use the existing capability/loss report;
- if an edit creates an invalid solid, keep the original document and discard the temporary transaction.

## Vision in editing

Vision is useful for phrases such as "make this side look like the reference" or for checking a supplied drawing, but it remains secondary evidence. A visual region must be bound back to stable model geometry before mutation. Exact dimensions/topology are validated deterministically.

## Future UX

The mobile interaction should support a conversation attached to the current document:

```text
User: make these two holes 6 mm
App:  [asks user to tap/select if needed]
Agent: targets Hole_04 + Hole_05; 4.5 -> 6.0 mm
App:  preview + exact validation
User: apply

User: now move the whole bracket 10 mm upward
Agent: preserves internal geometry, changes assembly transform only
```

The user can always drop into the command bar for precise correction.

## Research milestones

- N0: capture create + edit + query scope.
- N1: typed intent and edit-plan schema.
- N2: stable reference binding to `CadObjectRef`.
- N3: command engine and natural-language agent compile to the same tool operations.
- N4: modify an existing local OCCT document transactionally.
- N5: semantic diff + exact validation + undo/replay.
- N6: multimodal reference-driven edits through `VisionBridgeProvider`.
- N7: optional FreeCAD/Qwen-MM-style external provider and advanced history/assembly/FEM operations.
