# UV, textures and material assets

BrepSight must preserve more than visible geometry. UVs, texture bindings, material models and color-space semantics are part of the engineering/asset document and must participate in import, inspection, retopology and conversion-loss analysis.

## Core model

The engine tracks:

- one or more UV sets;
- PBR, Phong, Lambert, unlit and custom material models;
- texture assets stored as embedded data, external files, content URIs or generated assets;
- texture semantic: base color, normal, metallic, roughness, metallic-roughness, AO, emissive, opacity, specular, glossiness, height/displacement, etc.;
- sRGB vs linear/data color space;
- UV set index per texture;
- UV transform: offset, scale and rotation;
- wrap/filter modes;
- optional channel selection and strength.

Heavy texture bytes remain native/file-backed. Flutter receives descriptors, thumbnails and diagnostics only.

## Retopology attribute policy

Retopology changes vertex/face layout, therefore texture preservation is not automatic.

For every retopology result BrepSight must explicitly report whether it:

- preserved existing UVs;
- reprojected/transferred UVs;
- generated a new UV set;
- transferred normals/tangents;
- transferred vertex colors;
- retained material assignments;
- requires texture rebaking.

Skin weights and morph targets must never be silently claimed preserved unless a provider explicitly supports them.

## UV tool roadmap

### Inspection

- UV set list and active set;
- UV overlap detection;
- out-of-range coordinates;
- flipped/mirrored islands;
- missing UVs;
- texel-density estimates;
- texture resolution and missing-file diagnostics.

### Editing / generation

- planar / box / cylindrical / spherical projection;
- automatic seams;
- unwrap;
- island packing;
- rotate/scale/translate islands;
- normalize texel density;
- lightmap UV generation;
- UDIM-aware inspection as a later provider capability.

### Texture processing

- texture path relink;
- embed/extract where the destination format supports it;
- resize/compress;
- color-space correction warnings;
- normal-map convention detection/selection;
- bake source high-poly/scan attributes to retopologized low-poly mesh;
- base-color, normal, AO, curvature and displacement bake roadmap.

## Conversion-loss examples

- OBJ/MTL -> STL: UVs, textures and materials are lost.
- glTF -> OBJ/MTL: animation/PBR extensions may degrade even when base color/normal maps survive.
- FBX -> GLB: potentially high fidelity for mesh/PBR assets, but provider must report unsupported FBX-specific channels.
- retopologized quad OBJ -> STL: quad topology and UV/material semantics are lost through triangulation/STL limitations.
- textured scan -> 3MF: geometry/material support depends on the 3MF extensions used by the writer; the writer must report exact preservation.

## Product workflow

A realistic mobile flow should be possible without returning to a desktop just to keep textures attached:

`scan/import -> inspect material/UV -> retopology -> transfer/project UV -> bake textures -> inspect -> export/share`

UV and texture work is therefore a first-class tool family, not a decorative viewer feature.
