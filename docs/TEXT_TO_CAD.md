# Text-to-CAD / Voice-to-CAD concept

Status: research / feature branch only. This is intentionally not part of the production `main` path yet.

## Product goal

Allow a user to describe an engineering part in natural language or speech and obtain an **editable, validated engineering model**, not merely a visually plausible triangle mesh.

Example:

> Create a 60 x 40 x 8 mm plate, fillet the outer corners to R4, add four M4 clearance holes 5 mm from each edge, and place a 20 mm diameter 3 mm deep pocket in the center.

The system should produce a deterministic construction plan, execute it through a constrained CAD backend, validate dimensions/topology, and retain an editable operation history.

## Inspiration

The design is informed by projects such as `earthtojake/text-to-cad`, which treats CAD generation as a collection of agent skills and commonly emits STEP with optional STL/3MF/GLB outputs. BrepSight should reuse the *workflow idea*, not copy an opaque agent runtime into the mobile application.

A second reference is `QwenLM/Qwen-MM-Plugins`. Its architecture separates local media reading from the main reasoning model and exposes multimodal content through Skills/MCP. This is especially relevant when the main CAD reasoning model is text-only: a separate vision bridge can inspect a reference image, drawing, screenshot, or generated render and emit compact structured evidence for the CAD agent.

See `docs/VISION_BRIDGE.md` and `src/ai/visual_evidence.dart` for the BrepSight-specific contract.

## Proposed architecture

```text
Speech / text / image reference
          |
          +--> image -> local media reader -> VisionBridgeProvider -> VisualEvidence
          |
          v
 Intent normalizer
          |
          v
 Specification audit
  - missing dimensions?
  - contradictory constraints?
  - units?
  - manufacturing intent?
          |
          +----> targeted clarification when materially required
          |
          v
       CAD-IR
  - parameters
  - ordered operations
  - references
  - constraints
  - validation rules
          |
          v
 Deterministic executor
  - BrepSight command engine
  - OCCT-native operations
  - optional external/headless provider
          |
          v
 Geometry validation
  - solid validity
  - dimensions
  - volume / bbox
  - topology
  - named-feature existence
          |
          +----> canonical multi-view render
          |                  |
          |                  v
          |          VisionBridgeProvider
          |                  |
          |                  v
          |          visual discrepancy report
          |                  |
          +----> critique / rewrite loop
          |
          v
 EngineeringDocument
  - exact geometry when available
  - operation history
  - provenance
  - generated preview mesh
```

## Visual bridge for text-only CAD models

The goal is **not** to pretend a text-only model has gained native pixel understanding. Instead, pixels are handled by a separate provider and converted into typed evidence.

```text
pixels
  -> dynamic resize / crop / orientation handling
  -> local vision bridge
  -> VisualEvidence
  -> text-only CAD reasoner
```

Evidence may include:

- OCR text and dimension annotations;
- object/feature labels;
- normalized bounding regions;
- hole/slot/fillet/chamfer cues;
- material and surface cues;
- topology/alignment hints;
- confidence scores and warnings.

A local provider may advertise `supportsOffline=true` only if semantic image understanding requires no network request.

This bridge has two roles:

1. **generation input** — reference photos, sketches, engineering drawings, screenshots and annotated images;
2. **post-generation validation** — compare canonical BrepSight renders against reference evidence to detect missing features, count/layout mismatches, silhouette errors and obvious appearance differences.

Visual validation is advisory. Exact dimensions, hole diameters, B-Rep validity, solid count, topology and tolerances remain authoritative deterministic checks.

## CAD-IR, not arbitrary generated code

The default mobile path must not execute arbitrary Python, JavaScript, macros, FreeCAD scripts, or shell commands produced by a language model.

The model generates a restricted intermediate representation. Example:

```yaml
units: mm
parameters:
  width: 60
  height: 40
  thickness: 8
operations:
  - op: box
    id: base
    size: [60, 40, 8]
  - op: fillet
    target: base.vertical_edges
    radius: 4
  - op: hole_pattern
    diameter: 4.5
    count: 4
    offsets: [5, 5]
validation:
  bbox: [60, 40, 8]
  solids: 1
  through_holes: 4
```

Only registered operations can execute. Unsupported operations remain explicit instead of being converted into guessed geometry.

## Relationship to the mobile command line

Natural-language generation and the BrepSight command engine should converge on the same operation layer:

```text
User command:  FILLET #base R4
Natural text:  "round the vertical outer edges to 4 mm"
                         |
                         v
                  same CAD operation
```

This provides:

- deterministic replay;
- undo/redo;
- command history;
- editable parameters;
- a clean bridge from AI-generated intent to manual correction.

## Voice workflow

Voice should be treated as an input method, not a separate CAD engine:

```text
speech -> transcription -> engineering intent -> CAD-IR
```

The UI should echo interpreted dimensions and constraints before expensive execution when ambiguity is material.

Example confirmation card:

```text
Interpreted
Plate: 60 x 40 x 8 mm
Corners: R4
Holes: 4 x Ø4.5 through
Hole edge offset: 5 mm
Center pocket: Ø20 x 3 mm

[Generate] [Edit parameters]
```

## Provider strategy

The feature must not require one model vendor.

```text
CadIntentProvider
- local/on-device model (future)
- user-configured remote model
- cloud provider plugin
- deterministic template parser for simple commands

VisionBridgeProvider
- local/on-device vision bridge
- local OCR/CV pipeline
- user-configured remote vision model
- optional Qwen-MM-style harness adapter
```

The deterministic command parser should handle simple engineering language even without an LLM, for example:

- `box 20 30 5`
- `plate 60x40x8`
- `four M4 holes 5 mm from corners`

## Validation-first rule

A successful language-model response is not a successful CAD generation.

Completion requires executable geometry plus checks appropriate to the request. Candidate checks include:

- B-Rep validity;
- closed solid count;
- bounding box dimensions;
- measured hole diameters/depths;
- named feature count;
- minimum wall thickness when relevant;
- self-intersection / invalid topology;
- output-format capability report;
- optional visual discrepancy report against supplied references.

## Safety and honesty

- Never invent missing critical dimensions silently when they change fit or manufacturing intent.
- Mark inferred defaults explicitly.
- Never equate a generated mesh with editable parametric CAD.
- Treat visual/OCR output as untrusted evidence, not executable instructions.
- Generated manufacturing files remain drafts until independently reviewed.
- Do not automatically execute machine/toolpath commands.

## Mobile-specific interaction

The feature should exploit mobile strengths instead of imitating a desktop CAD workstation:

1. speak, type, or attach a reference image;
2. inspect a compact parameter/evidence card;
3. preview the result;
4. tap geometry to bind ambiguous references;
5. use the command line for precise correction;
6. optionally run visual + exact validation;
7. export/share directly.

Example follow-up:

> Make these two holes 6 mm instead.

The user taps the two holes, then the language/command layer receives stable geometry references rather than relying on screen coordinates.

## Research milestones

### R0 — preserve the idea
- branch and this design contract.

### R1 — CAD-IR schema
- boxes, cylinders, sketches, extrude, pocket, hole, pattern, fillet, chamfer, boolean, transform;
- reference model;
- validation schema.

### R2 — command-engine convergence
- command-line operations compile to CAD-IR;
- replayable history;
- undo/redo transaction semantics.

### R3 — natural-language prototype
- text -> CAD-IR;
- targeted clarification;
- deterministic execution;
- validation loop.

### R3V — offline visual bridge
- Qwen-MM-inspired local media adapter research;
- `VisualEvidence` schema;
- local OCR/vision backend benchmark;
- reference image -> structured evidence;
- canonical render -> discrepancy report.

### R4 — voice
- speech transcription;
- engineering parameter preview;
- background generation notification.

### R5 — agentic refinement
- Generate -> Execute -> Inspect -> Critique -> Rewrite;
- exact geometric measurements participate in critique;
- visual evidence participates as a secondary verifier, never as the sole engineering acceptance criterion.

## Non-goals for the first prototype

- unrestricted Python/macros;
- autonomous manufacturing submission;
- pretending every natural-language request is sufficiently specified;
- generating only STL and calling it CAD;
- claiming a text-only model natively understands pixels without a visual bridge.
