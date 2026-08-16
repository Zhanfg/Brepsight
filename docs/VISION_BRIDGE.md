# Local vision bridge for Text-to-CAD

Status: research / feature branch only.

## Inspiration

BrepSight should study the architecture of `QwenLM/Qwen-MM-Plugins`, especially its separation between:

- a local `core` capability that reads media without requiring an API key;
- MCP/Skill integration with an agent harness;
- a separate vision-capable bridge/model when the main reasoning model is text-only.

Qwen-MM-Plugins does not magically change a text-only language model into a native vision model. Its local `read_image` tool dynamically resizes an image for model consumption and returns a text summary plus image content through MCP. In harnesses such as Qwen Code, a dedicated vision-bridge model can transcribe/interpret the image for a text-only main model.

This separation is valuable for BrepSight because the best CAD reasoning model and the best mobile vision model do not need to be the same model.

## Proposed BrepSight architecture

```text
Reference image / sketch / drawing / screenshot
                    |
                    v
          Local media reader
        - decode / rotate / resize
        - dynamic resolution budget
        - crop / region extraction
                    |
                    v
            VisionBridgeProvider
       - local small VLM / OCR / CV
       - optional remote provider
                    |
                    v
              VisualEvidence
       - objects / features
       - OCR text / dimensions
       - symbols / material cues
       - regions + confidence
       - topology/alignment hints
                    |
                    v
          text-only CAD reasoner
                    |
                    v
                  CAD-IR
                    |
                    v
         deterministic CAD executor
                    |
                    v
          EngineeringDocument
```

The main text model only consumes compact structured evidence. Raw image pixels do not need to enter the text model's context.

## Offline mode

Offline must be a first-class path, not a fallback label.

```text
image
  -> Android/native decoder
  -> local vision bridge
  -> VisualEvidence JSON
  -> local or user-selected text model
  -> CAD-IR
```

A provider may advertise `supportsOffline=true` only when no network request is necessary for semantic image understanding.

Possible future local backends should be benchmarked independently for:

- OCR/dimension reading;
- engineering drawing symbols;
- feature recognition;
- multi-view object consistency;
- memory footprint;
- NPU/GPU/CPU latency;
- quantized Android viability.

The Qwen-MM architecture is an integration reference, not a mandatory runtime dependency.

## Generation-time use

Images may provide initial CAD intent:

- hand sketch;
- dimensioned drawing;
- screenshot from another CAD package;
- photo of a physical part;
- reference render;
- annotated image.

`VisualEvidence` must retain confidence and region references so the CAD agent can distinguish reliable OCR dimensions from uncertain visual guesses.

## Post-generation visual validation

Visual understanding is also useful after CAD generation.

```text
Reference evidence
       +
BrepSight canonical renders
  - front
  - side
  - top
  - isometric
       |
       v
local VisionBridgeProvider
       |
       v
VisualValidationReport
  - missing feature
  - wrong relative placement
  - silhouette mismatch
  - apparent count mismatch
  - material/appearance mismatch
       |
       v
CAD-IR critique / revision proposal
```

This is **advisory validation**. It must never replace deterministic engineering checks.

## Deterministic validation still wins

The following remain authoritative:

- exact bounding dimensions;
- hole diameter/depth;
- wall thickness;
- B-Rep validity;
- closed-solid count;
- topology validity;
- feature count from named CAD entities;
- tolerances and units.

A rendered model can look correct while being dimensionally wrong. Therefore a visual pass may request a rewrite, but final acceptance requires geometric checks.

## Security boundary

- Visual output is treated as untrusted evidence, not executable code.
- OCR text from drawings must not become shell/macros/scripts.
- The vision bridge emits typed evidence only.
- The CAD agent emits restricted CAD-IR only.
- No arbitrary Python, shell, FreeCAD macro, or JavaScript is executed by default.

## Initial research milestones

### V0 — contract
- `VisualEvidence`, `VisionBridgeProvider`, and `VisualValidationReport`.

### V1 — local image reader
- orientation handling;
- dynamic resolution;
- crops/regions;
- no network dependency.

### V2 — local vision backend benchmark
- compare several small vision/OCR backends on engineering screenshots and drawings.

### V3 — reference-image generation
- image -> VisualEvidence -> CAD-IR.

### V4 — rendered-model critique
- canonical multi-view render -> visual discrepancy report.

### V5 — hybrid validation loop
- exact geometric validators + visual validator -> critique -> deterministic CAD-IR revision.
