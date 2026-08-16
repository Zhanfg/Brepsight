export 'src/document/conversion.dart';
export 'src/document/engineering_document.dart';
export 'src/document/importer.dart';
export 'src/document/pipeline.dart';
export 'src/document/writer.dart';
export 'src/format_catalog.dart';
export 'src/material/material_assets.dart';
export 'src/mesh/retopology.dart';
export 'src/tasks/model_task.dart';

import 'package:flutter/services.dart';

import 'src/tasks/model_task.dart';

class CadLoadResult {
  const CadLoadResult({
    required this.ok,
    required this.displayName,
    required this.message,
    required this.formatId,
    required this.triangleCount,
    required this.errorCode,
  });

  final bool ok;
  final String displayName;
  final String message;
  final String formatId;
  final int triangleCount;
  final int errorCode;

  factory CadLoadResult.fromMap(Map<Object?, Object?> map) {
    return CadLoadResult(
      ok: map['ok'] == true,
      displayName: (map['displayName'] as String?) ?? '',
      message: (map['message'] as String?) ?? '',
      formatId: (map['formatId'] as String?) ?? 'unknown',
      triangleCount: (map['triangleCount'] as num?)?.toInt() ?? 0,
      errorCode: (map['errorCode'] as num?)?.toInt() ?? 0,
    );
  }
}

class NativeDocumentSummary {
  const NativeDocumentSummary({
    required this.handle,
    required this.sourcePath,
    required this.formatId,
    required this.triangleCount,
    required this.committed,
    required this.current,
  });

  final int handle;
  final String sourcePath;
  final String formatId;
  final int triangleCount;
  final bool committed;
  final bool current;

  factory NativeDocumentSummary.fromMap(Map<Object?, Object?> map) {
    return NativeDocumentSummary(
      handle: (map['handle'] as num).toInt(),
      sourcePath: (map['sourcePath'] as String?) ?? '',
      formatId: (map['formatId'] as String?) ?? 'unknown',
      triangleCount: (map['triangleCount'] as num?)?.toInt() ?? 0,
      committed: map['committed'] == true,
      current: map['current'] == true,
    );
  }
}

class CadEngine {
  CadEngine._();

  static final CadEngine instance = CadEngine._();
  static const MethodChannel _channel = MethodChannel('cad_engine/methods');

  Future<int> createViewport({required int width, required int height}) async {
    final id = await _channel.invokeMethod<int>('createViewport', {'width': width, 'height': height});
    if (id == null) throw StateError('Native viewport did not return a texture id.');
    return id;
  }

  Future<void> resizeViewport({required int width, required int height}) {
    return _channel.invokeMethod<void>('resizeViewport', {'width': width, 'height': height});
  }

  Future<void> disposeViewport() => _channel.invokeMethod<void>('disposeViewport');

  Future<String?> openDocument() => _channel.invokeMethod<String>('openDocument');

  Future<bool> requestBackgroundProcessingPermission() async =>
      await _channel.invokeMethod<bool>('requestBackgroundProcessingPermission') ?? false;

  Future<bool> canShowTaskNotifications() async =>
      await _channel.invokeMethod<bool>('canShowTaskNotifications') ?? false;

  Future<void> promoteBackgroundTask(ModelTaskSnapshot task) =>
      _channel.invokeMethod<void>('promoteBackgroundTask', _taskMap(task));

  Future<void> updateBackgroundTask(ModelTaskSnapshot task) =>
      _channel.invokeMethod<void>('updateBackgroundTask', _taskMap(task));

  Future<void> finishBackgroundTask(ModelTaskSnapshot task) =>
      _channel.invokeMethod<void>('finishBackgroundTask', {
        ..._taskMap(task),
        'success': task.state == ModelTaskState.completed,
      });

  Map<String, Object?> _taskMap(ModelTaskSnapshot task) => <String, Object?>{
        'taskId': task.id,
        'title': task.title,
        'stage': task.progress.stageLabel.isNotEmpty
            ? task.progress.stageLabel
            : task.progress.stage.name,
        'progress': task.progress.percent,
        'message': task.message,
      };

  Future<int> beginDocumentTransaction({
    required String path,
    required String formatId,
  }) async {
    final handle = await _channel.invokeMethod<int>(
      'beginDocumentTransaction',
      {'path': path, 'formatId': formatId},
    );
    if (handle == null || handle <= 0) {
      throw StateError('Native document transaction did not return a handle.');
    }
    return handle;
  }

  /// Commits [handle] as the visible/current native document.
  /// Returns the previously-current handle when one existed.
  Future<int?> commitDocumentTransaction(int handle) =>
      _channel.invokeMethod<int>('commitDocumentTransaction', {'handle': handle});

  Future<bool> discardDocumentTransaction(int handle) async =>
      await _channel.invokeMethod<bool>(
        'discardDocumentTransaction',
        {'handle': handle},
      ) ??
      false;

  Future<int?> getCurrentDocumentHandle() =>
      _channel.invokeMethod<int>('getCurrentDocumentHandle');

  Future<NativeDocumentSummary?> getDocumentSummary(int handle) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getDocumentSummary',
      {'handle': handle},
    );
    return raw == null ? null : NativeDocumentSummary.fromMap(raw);
  }

  Future<CadLoadResult> loadModel(String path) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('loadModel', {'path': path});
    return CadLoadResult.fromMap(raw ?? const {});
  }

  Future<void> fitAll() => _channel.invokeMethod<void>('fitAll');

  Future<void> setProjection(String projection) =>
      _channel.invokeMethod<void>('setProjection', {'projection': projection});

  Future<void> setDisplayMode(String mode) =>
      _channel.invokeMethod<void>('setDisplayMode', {'mode': mode});

  Future<void> orbit(double dx, double dy) =>
      _channel.invokeMethod<void>('orbit', {'dx': dx, 'dy': dy});

  Future<void> pan(double dx, double dy) =>
      _channel.invokeMethod<void>('pan', {'dx': dx, 'dy': dy});

  Future<void> zoom(double factor) =>
      _channel.invokeMethod<void>('zoom', {'factor': factor});
}
