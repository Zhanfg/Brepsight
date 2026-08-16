# Android build and release line

BrepSight keeps an Android APK build available from CI from the beginning of development. A repository change should not be considered buildable merely because Dart/C++ source exists.

## CI baseline

Pinned toolchain:

- Flutter 3.44.8 stable
- Java 17
- Android SDK supplied by the GitHub-hosted Ubuntu runner
- Android minSdk 24

The Android application scaffold is generated deterministically from the pinned Flutter SDK when it is not committed in the repository. The application id is `dev.brepsight`.

## Pull requests and main

`.github/workflows/android-apk.yml` runs on:

- pushes to `main`;
- pull requests;
- manual `workflow_dispatch`.

The job:

1. checks out source;
2. installs the pinned Flutter SDK;
3. generates/normalizes the Android scaffold;
4. runs `flutter analyze`;
5. runs tests when Dart tests exist;
6. builds a **debug-signed installable APK**;
7. copies the APK to `dist/` with run number and short commit SHA;
8. writes a SHA-256 checksum;
9. uploads both as a GitHub Actions artifact.

Debug signing is intentional for continuous install testing. The APK can be sideloaded on Android but is not a production release signature.

## Production signing

Production signing must use a stable owner-controlled Android signing key. The key, passwords, tokens, and other secrets must never be committed to this repository or printed in logs.

A later release workflow should read signing material only from protected GitHub Actions secrets/environments and produce:

- signed universal APK;
- optional split-per-ABI APKs;
- Android App Bundle (`.aab`) when distribution requires it;
- checksums;
- provenance/build metadata.

Until release signing is configured, CI artifacts are explicitly labeled `debug`.

## Artifact naming

Example:

```text
BrepSight-42-a1b2c3d-debug.apk
BrepSight-42-a1b2c3d-debug.apk.sha256
```

This makes every artifact traceable to one CI run and commit.

## Build acceptance rule

A feature that changes Android/Flutter/native build behavior is not complete until the Android APK workflow passes. Parser-only/documentation changes may still trigger the build so integration breakage is found early.
