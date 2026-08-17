# FreeCAD FCStd read-only subset

BrepSight does not embed FreeCAD and does not execute FCStd document code. The current provider treats every `.FCStd` / `.FCBak` file as untrusted input and supports only a deliberately narrow, independently parsed saved-document subset.

## Manifest V2 boundary

The Android preprocessor may emit only the following BrepSight-owned records to native code:

- document source path and object count;
- object name, declared FreeCAD type and label;
- the object's `Placement` (`Px/Py/Pz/Q0/Q1/Q2/Q3`);
- hierarchy edges only from `Property name="Group" type="App::PropertyLinkList"`;
- `ViewProvider` visibility and `ShapeColor` presentation metadata;
- BREP/BRP members explicitly referenced by `Part::PropertyPartShape`.

Other `App::PropertyLink`, `PropertyLinkList`, `PropertyLinkSub*`, expression, dependency, attachment, Python, macro, pickle or workbench-specific records are not treated as tree ownership merely because they reference another object.

## Transform semantics

Native import composes group-parent placement with child placement before building the display mesh. Group cycles, excessive depth, unknown objects and multiple-parent ambiguity are rejected. Exact saved BREP payload remains paired with the parsed world transform in the FCStd object payload; BrepSight does not recompute parametric geometry.

## Presentation semantics

`GuiDocument.xml` is parsed with the same DTD/entity/network restrictions as `Document.xml`. Current V2 support preserves and applies:

- `Visibility` when serialized as a boolean property;
- `ShapeColor` when serialized as a 32-bit `App::PropertyColor` value.

Saved BREP geometry is partitioned into provider-neutral contiguous draw ranges. Effective visibility follows the explicit Group-parent chain: hidden objects remain in the document and exact payload but are skipped by the default GLES draw path and excluded from visible `Fit All` bounds. Visible ranges use their decoded `ShapeColor` as the base shader color; formats without draw ranges retain the existing default single-draw behavior.

This is still not full FreeCAD presentation fidelity. Draw-range application currently covers object-level saved-BREP visibility and base color only.

## Explicitly not covered yet

- arbitrary App::Link ownership semantics and Link arrays;
- PartDesign Body/Tip/Origin tree semantics beyond explicit Group edges;
- Attachment/Support-driven transforms;
- interactive per-object show/hide state changes from Flutter;
- per-face colors, transparency, line/point styles and FreeCAD display modes;
- thumbnails;
- expressions, recompute, Python or workbench runtime state.
