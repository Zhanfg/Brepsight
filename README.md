# BrepSight

BrepSight is a **Flutter-first mobile CAD viewer and inspection toolkit**. The project is a clean rebuild rather than a patched Qt APK.

## What already exists

- Flutter Material 3 app shell with Chinese UI.
- No forced Open Sans UI font; Android system font fallback is used.
- Android system file picker and cache import flow.
- Flutter `Texture` viewport backed by `TextureRegistry.SurfaceProducer`.
- Kotlin lifecycle bridge.
- Native C++ EGL/OpenGL ES renderer that proves the Flutter -> Surface -> JNI -> GLES path without any Qt/QML runtime dependency.
- Viewer gestures and commands are already wired to native code.
- OCCT-facing load command is deliberately a stub until a fresh Android OCCT build is linked.

## Important boundary

The supplied original `libCADAssistant.so` is intentionally **not** copied into this project. It links directly against Qt 5 and would keep the old framework alive inside the new app.

## Next implementation step

Replace the proof renderer in `packages/cad_engine/android/src/main/cpp/cad_engine_jni.cpp` with a clean OCCT viewer implementation. Start with a generated box, then STL, then STEP/XCAF.

## Build

A current Flutter + Android SDK/NDK environment is required:

```bash
./tool/bootstrap_flutter.sh
flutter build apk --debug
```

The repository currently contains the Stage 1 Flutter shell and native rendering bridge. A fresh Android OCCT build is the next engine milestone.
