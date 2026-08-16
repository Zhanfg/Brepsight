# Retopology

Retopology is a first-class BrepSight workflow, not a mesh-repair checkbox.

## Why it exists

Triangle meshes are excellent interchange/render/printing representations but are often poor editing topology. Real mobile workflows include:

- scan -> dense triangle mesh -> quad mesh -> Blender/Rhino/SubD editing;
- STL/OBJ received on a phone -> retopologize -> continue modeling on desktop;
- high-poly sculpt -> lower-density quad mesh -> subdivision/sculpt continuation;
- hard-surface triangulated asset -> feature-aligned quads -> downstream edits;
- scan -> quad layout -> surface fitting -> approximate B-Rep/STEP reverse engineering.

Retopology must therefore be treated separately from watertight repair, decimation, voxel remeshing, and mesh-to-CAD fitting.

## Product modes

### Automatic quad remesh

Mobile-first one-tap operation with advanced options behind a sheet:

- target face count or ratio;
- quad-dominant or all-quad target;
- preserve boundary;
- preserve sharp features;
- symmetry axis;
- project result back to source surface;
- attribute transfer.

The first planned native backend is `retopo.quadriflow` for automatic triangle-to-quad conversion. Android integration must be headless and use the permissive dependency configuration (`BUILD_FREE_LICENSE=ON`); no desktop UI/runtime is shipped.

### Guided field-aligned retopology

A later `retopo.instant-meshes` provider targets interactive field-aligned workflows:

- orientation-field visualization;
- orientation brush/guides;
- position-field visualization;
- feature/boundary constraints;
- live coarse preview before final solve.

This mode is especially valuable on tablets/stylus devices and avoids pretending that a fully automatic solve always produces artist-quality edge flow.

## Use-case presets

`RetopologyUseCase` is semantic rather than cosmetic:

- `generalModeling` — balanced face count and surface fidelity;
- `subdivision` — prioritize regular quad flow and pole quality;
- `sculpting` — even distribution and smooth projection;
- `hardSurface` — prioritize sharp/boundary preservation;
- `animationAssist` — provide a useful starting mesh but explicitly warn that automatic topology is not guaranteed deformation-ready;
- `reverseEngineering` — prioritize feature alignment and surface deviation metrics for later curve/surface fitting.

## Quality report

Every solve returns a report. The UI must expose at least:

- input and output face counts;
- quad / triangle / n-gon counts;
- quad ratio;
- manifold status when known;
- boundary preservation result;
- mean surface deviation when available;
- maximum surface deviation when available;
- warnings for unsupported attribute transfer or topology limitations.

A retopology result must never be presented as equivalent to the source solely because it looks similar.

## Attribute policy

Retopology changes connectivity, so attributes need explicit handling:

- normals can be recomputed or transferred/projected;
- UVs may require reprojection and cannot be assumed lossless;
- vertex colors can be barycentrically/projectively transferred;
- material assignments should be projected by source surface/object where possible;
- skin weights and morph targets are high-risk transfers and are not launch requirements.

The `EngineeringDocument` capability set includes topology/mesh attributes so export and conversion loss reports can describe these losses.

## Export semantics

Quad topology is meaningful data.

- OBJ can preserve polygon/quad topology when the writer is configured accordingly.
- Formats/workflows that require triangles must report `quadTopology` as degraded/lost before export.
- A quad mesh exported to STL is intentionally triangulated; BrepSight must not imply the editable quad topology survived.

## Scan-to-CAD relationship

Retopology is an intermediate representation, not automatic CAD reconstruction:

`scan -> triangle mesh -> retopology -> feature/patch extraction -> curve/surface fitting -> B-Rep -> STEP`

The retopology stage can greatly improve patch layout and downstream fitting, but the final B-Rep remains fitted/approximate and must carry deviation/tolerance provenance.

## Mobile performance rules

- geometry remains native-side behind document handles;
- solver execution is cancellable and runs off the UI thread;
- preview may solve at a lower target density than final output;
- memory budgets are explicit;
- large scans may pre-decimate a working copy while retaining the original source document;
- retopology is transactional: failed/cancelled solves never replace the current document.
