# Security model

BrepSight opens complex third-party engineering files. Every imported document is untrusted input.

## Core rule

**Viewing a file must never execute code from that file.**

This applies even when the source application normally supports macros, Python objects, plugins, external references or embedded automation.

## Import pipeline

```text
Android URI
   |
   v
read-only app cache copy
   |
   v
size/signature preflight
   |
   v
provider probe
   |
   v
bounded parser worker
   |
   v
temporary neutral document
   |
   v
validation + diagnostics
   |
   v
commit to visible scene
```

A parser failure must discard the temporary document and leave the current visible scene intact.

## Archive/container limits

ZIP/container formats such as FCStd must enforce limits before full extraction:

- maximum source file size;
- maximum entry count;
- maximum single-entry uncompressed size;
- maximum total uncompressed size;
- maximum compression ratio;
- path traversal rejection (`../`, absolute paths, drive prefixes);
- symlink/special-file rejection where applicable;
- duplicate critical entry handling.

## XML

XML readers must:

- disable DTD processing where possible;
- disable external general entities;
- disable external parameter entities;
- never fetch network resources;
- apply nesting/depth and total-text limits;
- reject invalid encodings safely.

## FCStd

The FCStd reader is deliberately narrower than FreeCAD itself.

Allowed:

- inspect `Document.xml` and supported `GuiDocument.xml` metadata;
- read stored BREP/BRP geometry;
- read thumbnails and benign embedded resources within limits.

Prohibited:

- importing Python modules named by the document;
- running macros;
- restoring pickled Python objects;
- executing constructors from serialized object metadata;
- resolving external XML entities;
- writing into the source archive.

## Native parser hardening

All native importers should use:

- integer-overflow-safe size calculations;
- explicit allocation ceilings;
- recursion/depth limits;
- cancellation checks for long imports;
- fuzz-test corpora for high-risk parsers;
- sanitizers in host CI where practical;
- malformed-file regression tests.

## Isolation

The public Flutter API must not assume parsers execute in the UI/native process.

Risky or experimental providers should be movable to an Android isolated worker process later. The provider boundary should communicate only:

- progress;
- diagnostics;
- normalized scene/result data or a validated cache artifact;
- cancellation.

## External references

By default BrepSight does not automatically dereference network or arbitrary filesystem links embedded in a model.

External textures/parts/resources require an explicit user-approved resolution path. Remote URLs are not fetched automatically.

## Proprietary bridges

A proprietary or desktop conversion bridge is outside the trusted open-core importer set. Converted output must still pass normal BrepSight validation before display.

## Reporting

Import diagnostics should distinguish:

- malformed file;
- unsupported format/version;
- resource limit exceeded;
- unsupported embedded feature;
- security policy rejection;
- parser/internal error.

Do not collapse all failures into "file cannot be opened"; users need to know whether the file is unsupported, damaged or intentionally blocked.
