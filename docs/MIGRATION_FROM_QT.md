# Qt -> Flutter migration

## Confirmed from the supplied APK

- UI stack: Qt 5.9.9 + QML/Qt Quick Controls.
- Main native binary: `libCADAssistant.so`, about 66 MB.
- Native binary is monolithic and links directly to multiple Qt shared libraries.
- Existing APK contains OpenCASCADE-related symbols and import support for formats including STL, STEP/STP, IGES, OBJ, PLY, glTF, 3DM, DXF, IFC, BREP and others.
- The old UI hard-coded Open Sans in QML; that path is discarded in the Flutter rebuild.

## Migration rule

Do **not** copy `libCADAssistant.so` into the Flutter project as the long-term engine. Doing that keeps Qt as a runtime dependency and defeats the refactor.

## Stages

1. **Flutter shell + native Surface proof** — included in this package.
2. **Fresh OCCT Android build** — link V3d_Viewer/AIS and display a generated primitive.
3. **STL importer** — load, fit, orbit/pan/zoom, shaded/wireframe.
4. **STEP/IGES + XCAF tree** — assembly hierarchy and properties.
5. **Measurements and sectioning** — distance/angle/radius, clipping plane.
6. **Mesh diagnostics** — triangle count, bounds, normals, non-manifold/open-edge checks.
7. **Export/share/recent files** — Android-first workflow.

At every stage, the Flutter-facing API remains stable so the UI is not rewritten again.
