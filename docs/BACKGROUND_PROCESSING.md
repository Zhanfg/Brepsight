# Background engineering tasks

BrepSight treats long-running model work as a first-class product workflow. Retopology, scan reconstruction, photogrammetry, mesh repair, reverse engineering, texture baking and large format conversion must not depend on the lifetime of a Flutter screen.

## Execution boundary

- Flutter owns task presentation and user intent.
- The Android foreground service owns user-visible background execution state.
- Native workers own geometry/mesh/point-cloud/texture memory and heavy computation.
- MethodChannel carries task ids, lightweight progress, summaries and commands only.
- Heavy buffers must never be streamed through MethodChannel.

The default scheduler runs **one high-cost geometry task at a time**. Additional high-cost tasks should queue. This is deliberate for mobile RAM, thermal and battery behavior.

## Android permission model

There is no generic Android runtime permission that means "keep this app alive forever".

BrepSight requests `POST_NOTIFICATIONS` so a user-started long task remains visible and controllable. A task must be promoted while the app is in an allowed foreground/user-initiated state.

The Android plugin declares:

- `FOREGROUND_SERVICE`;
- `FOREGROUND_SERVICE_SPECIAL_USE`;
- a `specialUse` subtype describing user-initiated long-running engineering model processing.

Do not request battery-optimization exemptions by default. Do not promise survival after force-stop, reboot, OEM kill behavior, or system termination.

## Notification behavior

Android 16 / API 36 uses `Notification.ProgressStyle` when available. Older Android versions use the normal determinate progress template.

Suggested stages:

1. Preparing
2. Reading
3. Analyzing
4. Solving / reconstructing
5. Projecting
6. Transferring attributes
7. UV generation / texture baking when applicable
8. Writing
9. Validating
10. Finalizing

The notification exposes a Cancel action. Cancellation is cooperative: native algorithms must check a cancellation token at safe checkpoints and leave the currently committed document untouched.

## Task state contract

`queued -> running -> completed | failed | cancelled`

`paused` is reserved for providers that can safely checkpoint and resume.

Every task should persist enough lightweight metadata to restore UI state after Activity recreation:

- task id and kind;
- source and target document handles/paths as safe references;
- stage and progress;
- output path when available;
- diagnostics and terminal status.

Large native documents themselves are not serialized through Flutter.

## Current implementation status

Implemented foundation:

- Dart `ModelTask*` contracts;
- notification permission bridge;
- Android foreground `ModelTaskService`;
- Android 16 progress-style best-effort notification with legacy fallback;
- cancellation request registry;
- task notification promote/update/finish bridge.

Still required before claiming true background model processing end-to-end:

- native task scheduler/worker ownership independent from Flutter widgets;
- native cancellation token bridge;
- persistent lightweight task journal;
- provider integration (QuadriFlow, reconstruction, conversion, etc.);
- process-death/restart recovery policy per provider.
