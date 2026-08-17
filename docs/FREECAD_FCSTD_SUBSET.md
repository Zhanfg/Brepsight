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

`GuiDocument.xml` is parsed with the same DTD/entity/network restrictions as `Document.xml`. Current V2 payload preserves:

- `Visibility` when serialized as a boolean property;
- `ShapeColor` when serialized as a 32-bit `App::PropertyColor` value.

These values are metadata until the viewer's per-object render state is connected. Their presence in the payload must not be advertised as full FreeCAD material or presentation fidelity.

## Explicitly not covered yet

- arbitrary App::Link ownership semantics and Link arrays;
- PartDesign Body/Tip/Origin tree semantics beyond explicit Group edges;
- Attachment/Support-driven transforms;
- per-face colors, transparency, line/point styles and display modes;
- thumbnails;
- expressions, recompute, Python or workbench runtime state.
