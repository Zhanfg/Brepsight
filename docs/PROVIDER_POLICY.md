# Provider policy

BrepSight supports a broad format ecosystem through replaceable providers rather than one monolithic parser library.

## Provider classes

- `core.*` — BrepSight Apache-2.0 source.
- `occt.*` — Open CASCADE-backed exact CAD readers.
- `opennurbs.*` — Rhino 3DM reader.
- `lib3mf` / `additive.*` — additive manufacturing readers.
- `assimp.*` / `scene.*` — DCC/mesh/scene readers.
- `drawing.*` — open read-only drafting readers such as DXF.
- `point.*` — point-cloud readers.
- `bim.*` — BIM/AEC providers.
- `cae.*` — simulation/result readers.
- `toolpath.*` / `slice.*` — manufacturing path/slice viewers.
- `bridge.*` — optional licensed or external providers.

## Mandatory runtime contract

Every provider must expose:

1. file probe confidence independent of filename extension;
2. source format/version when detectable;
3. progress + cancellation;
4. import into a temporary document;
5. status: success / partial / failed;
6. preserved-capability flags;
7. warnings/data-loss diagnostics;
8. memory/file-size estimates where practical;
9. safe failure without replacing the currently visible document.

## License boundary

The default APK remains buildable without proprietary SDKs or GPL-only parser libraries. Optional commercial SDKs are isolated behind provider interfaces. GPL readers are not dynamically or statically linked into the Apache application build unless the entire resulting distribution strategy is deliberately changed and reviewed.

## Security boundary

Engineering files are untrusted input. Importers must not execute embedded scripts, macros, machine toolpaths or external references automatically. Container/XML formats require zip-bomb, path traversal and external-entity protections. Long-running/high-risk importers should be eligible for process isolation later.
