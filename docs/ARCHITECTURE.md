# Architecture

## Target stack

```text
Flutter / Dart
├─ Material 3 UI
├─ file flow / recent models / settings
├─ gesture layer
└─ Texture widget
       │ textureId
       ▼
Android Flutter plugin (Kotlin)
├─ TextureRegistry.SurfaceProducer
├─ Android Storage Access Framework
└─ lifecycle + JNI bridge
       │ Surface / commands
       ▼
C++ native core
├─ Stage 1: EGL/OpenGL ES proof renderer (included)
├─ Stage 2: OpenCASCADE V3d_Viewer + AIS_InteractiveContext
├─ importers: STL / STEP / IGES / OBJ / PLY / glTF ...
└─ model services: tree / properties / measure / section / mesh checks
```

## Why this replaces Qt instead of wrapping it

The original APK's ~66 MB `libCADAssistant.so` directly depends on Qt5Quick, Qt5Widgets,
Qt5Gui, Qt5Qml, Qt5Network, Qt5AndroidExtras and Qt5Core. It therefore cannot become a
clean Flutter native core by simply loading that `.so`.

The new project treats the old APK as a behavioral reference only. OpenCASCADE is rebuilt
for Android and linked into a new native library with a small, stable boundary.

## Rendering

Use Flutter's Android `TextureRegistry.SurfaceProducer` and hand the produced Android
`Surface` to native C++. The included Stage-1 renderer creates an EGL context and renders
without Qt. OCCT replaces only the proof renderer in Stage 2, so Flutter UI code does not
need another rewrite.

## Command split

- Low-frequency UI commands: MethodChannel initially.
- High-frequency camera/selection traffic: move to C ABI + Dart FFI when OCCT is linked.
- Long-running import/meshing: C++ worker thread; return progress/events asynchronously.

## Fonts

No bundled application UI font. Flutter/Android system typography is used, allowing native
CJK fallback. CAD annotation fonts are a separate concern inside the OCCT renderer and must
not be replaced by the UI font.
