# Assimp DCC provider subset

BrepSight uses Assimp as an **optional mesh/DCC provider**, not as a blanket claim that every Assimp-supported format is production-ready on Android.

## Pinned provider build

The Android SDK is pinned to Assimp `v6.0.5` at commit `392a658f9c271be965271f45e7521a1b80ea4392` and is built for `arm64-v8a` / Android API 24 as a shared library.

BrepSight deliberately enables only these Assimp importers in the current SDK:

- FBX;
- COLLADA / DAE;
- PLY;
- OFF.

The build disables exporters, tests/tools/samples/docs and unvalidated import packs. In particular, USD is not enabled through this provider and native Blender `.blend` is not enabled or advertised.

3MF remains on BrepSight's dedicated lib3mf path rather than being routed through Assimp.

## Current runtime mapping

For the enabled DCC subset, BrepSight currently preserves:

- scene node names and parent relationships;
- node-local transforms;
- world-space display geometry produced by composing the node hierarchy;
- triangle topology after Assimp triangulation;
- source normals when available, with generated face normals as fallback;
- UV channel 0 when available;
- material name and diffuse base color;
- diffuse texture-reference count;
- camera and animation counts as metadata;
- tangents/bitangents presence as metadata;
- provider-neutral object presentation and draw ranges, allowing the same object visibility UI used by other hierarchical providers.

The current GLES path renders object/draw-range base color. Texture sampling, animation playback, imported-camera activation and tangent-space material shading are not implemented yet; the provider records warnings instead of silently claiming those features were preserved visually.

## Validation status

### Semantically validated with clean-room fixtures

- **DAE** — nested hierarchy, local/world transforms, material diffuse color, camera metadata and partial-loss warning;
- **PLY** — triangle geometry and bounds;
- **OFF** — triangle geometry and bounds.

### Built into Android but not yet representative-corpus validated

- **FBX** — the pinned Android SDK includes the FBX importer and the runtime route is compiled into the APK, but BrepSight does not mark FBX complete until an independently acceptable representative fixture/corpus validates hierarchy/material behavior.

This distinction is intentional: compile/link support is weaker evidence than actual file semantics.

## Safety / limits

The importer applies explicit mobile limits to hierarchy depth, node count, material count and expanded display vertices. It rejects invalid node mesh indices and non-finite transforms. The provider does not execute embedded scripts or external application logic.

## Explicitly outside this slice

- native `.blend` parsing;
- USD / USDZ;
- Alembic;
- 3DS and additional Assimp importers;
- skeletal/vertex animation playback;
- texture image decode/sampling and PBR material reconstruction;
- camera switching;
- source-scene editing or DCC round-trip export.
