enum ModelTaskKind {
  importModel,
  exportModel,
  convertFormat,
  retopology,
  meshRepair,
  scanReconstruction,
  photogrammetry,
  reverseEngineering,
  textureProcessing,
  uvProcessing,
}

enum ModelTaskState {
  queued,
  running,
  paused,
  completed,
  failed,
  cancelled,
}

enum ModelTaskStage {
  preparing,
  reading,
  analyzing,
  reconstructing,
  solving,
  projecting,
  transferringAttributes,
  generatingUv,
  bakingTextures,
  optimizing,
  writing,
  validating,
  finalizing,
}

class ModelTaskProgress {
  const ModelTaskProgress({
    required this.stage,
    required this.fraction,
    this.stageLabel = '',
    this.completedUnits,
    this.totalUnits,
  }) : assert(fraction >= 0 && fraction <= 1);

  final ModelTaskStage stage;
  final double fraction;
  final String stageLabel;
  final int? completedUnits;
  final int? totalUnits;

  int get percent => (fraction * 100).round().clamp(0, 100).toInt();
}

class ModelTaskSnapshot {
  const ModelTaskSnapshot({
    required this.id,
    required this.kind,
    required this.title,
    required this.state,
    required this.progress,
    required this.userInitiated,
    this.documentHandle,
    this.outputPath,
    this.message = '',
    this.createdAt,
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final ModelTaskKind kind;
  final String title;
  final ModelTaskState state;
  final ModelTaskProgress progress;
  final bool userInitiated;
  final int? documentHandle;
  final String? outputPath;
  final String message;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get isTerminal =>
      state == ModelTaskState.completed ||
      state == ModelTaskState.failed ||
      state == ModelTaskState.cancelled;
}

abstract class ModelTaskController {
  Stream<ModelTaskSnapshot> watch(String taskId);
  Future<ModelTaskSnapshot?> snapshot(String taskId);
  Future<List<ModelTaskSnapshot>> activeTasks();
  Future<void> cancel(String taskId);
}

/// Platform host responsibilities for long-running engineering work.
///
/// The host keeps the task visible/controllable while the UI is backgrounded.
/// Actual geometry, point clouds and textures stay in the native task manager.
abstract class BackgroundTaskHost {
  Future<bool> requestUserVisibleBackgroundPermission();
  Future<bool> canShowTaskNotifications();
  Future<void> promote(ModelTaskSnapshot task);
  Future<void> update(ModelTaskSnapshot task);
  Future<void> finish(ModelTaskSnapshot task);
}
