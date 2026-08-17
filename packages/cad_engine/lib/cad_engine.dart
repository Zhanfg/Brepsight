import 'dart:convert';

export 'src/commands/command_engine.dart';
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
    required this.hasUv,
    required this.hasNormals,
    required this.exactGeometry,
    required this.rootObjectCount,
    required this.hierarchyNodeCount,
    required this.errorCode,
  });

  final bool ok;
  final String displayName;
  final String message;
  final String formatId;
  final int triangleCount;
  final bool hasUv;
  final bool hasNormals;
  final bool exactGeometry;
  final int rootObjectCount;
  final int hierarchyNodeCount;
  final int errorCode;

  factory CadLoadResult.fromMap(Map<Object?, Object?> map) {
    return CadLoadResult(
      ok: map['ok'] == true,
      displayName: (map['displayName'] as String?) ?? '',
      message: (map['message'] as String?) ?? '',
      formatId: (map['formatId'] as String?) ?? 'unknown',
      triangleCount: (map['triangleCount'] as num?)?.toInt() ?? 0,
      hasUv: map['hasUv'] == true,
      hasNormals: map['hasNormals'] == true,
      exactGeometry: map['exactGeometry'] == true,
      rootObjectCount: (map['rootObjectCount'] as num?)?.toInt() ?? 0,
      hierarchyNodeCount: (map['hierarchyNodeCount'] as num?)?.toInt() ?? 0,
      errorCode: (map['errorCode'] as num?)?.toInt() ?? 0,
    );
  }
}

class CadExportResult {
  const CadExportResult({
    required this.ok,
    required this.displayName,
    required this.formatId,
    required this.destinationUri,
  });

  final bool ok;
  final String displayName;
  final String formatId;
  final String destinationUri;

  factory CadExportResult.fromMap(Map<Object?, Object?> map) {
    return CadExportResult(
      ok: map['ok'] == true,
      displayName: (map['displayName'] as String?) ?? '',
      formatId: (map['formatId'] as String?) ?? 'unknown',
      destinationUri: (map['destinationUri'] as String?) ?? '',
    );
  }
}

class CadSplitResult {
  const CadSplitResult({
    required this.ok,
    required this.partCount,
    required this.formatId,
    required this.destinationUri,
  });

  final bool ok;
  final int partCount;
  final String formatId;
  final String destinationUri;

  factory CadSplitResult.fromMap(Map<Object?, Object?> map) {
    return CadSplitResult(
      ok: map['ok'] == true,
      partCount: (map['partCount'] as num?)?.toInt() ?? 0,
      formatId: (map['formatId'] as String?) ?? 'unknown',
      destinationUri: (map['destinationUri'] as String?) ?? '',
    );
  }
}

class CadMergeResult {
  const CadMergeResult({
    required this.ok,
    required this.sourceCount,
    required this.outputPath,
    required this.formatId,
  });

  final bool ok;
  final int sourceCount;
  final String outputPath;
  final String formatId;

  factory CadMergeResult.fromMap(Map<Object?, Object?> map) {
    return CadMergeResult(
      ok: map['ok'] == true,
      sourceCount: (map['sourceCount'] as num?)?.toInt() ?? 0,
      outputPath: (map['outputPath'] as String?) ?? '',
      formatId: (map['formatId'] as String?) ?? 'unknown',
    );
  }
}

class MeshInspection {
  const MeshInspection({
    required this.triangleCount,
    required this.uniqueVertexCount,
    required this.openEdgeCount,
    required this.nonManifoldEdgeCount,
    required this.connectedComponentCount,
    required this.degenerateTriangleCount,
    required this.surfaceArea,
    required this.enclosedVolume,
    required this.closed,
    required this.unitKnown,
    required this.unitLabel,
    required this.boundsMin,
    required this.boundsMax,
    required this.size,
  });

  final int triangleCount;
  final int uniqueVertexCount;
  final int openEdgeCount;
  final int nonManifoldEdgeCount;
  final int connectedComponentCount;
  final int degenerateTriangleCount;
  final double surfaceArea;
  final double enclosedVolume;
  final bool closed;
  final bool unitKnown;
  final String unitLabel;
  final List<double> boundsMin;
  final List<double> boundsMax;
  final List<double> size;

  bool get manifold => nonManifoldEdgeCount == 0;

  factory MeshInspection.fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    List<double> vector(String key) =>
        ((map[key] as List<dynamic>?) ?? const <dynamic>[])
            .map((value) => (value as num).toDouble())
            .toList(growable: false);
    return MeshInspection(
      triangleCount: (map['triangleCount'] as num?)?.toInt() ?? 0,
      uniqueVertexCount: (map['uniqueVertexCount'] as num?)?.toInt() ?? 0,
      openEdgeCount: (map['openEdgeCount'] as num?)?.toInt() ?? 0,
      nonManifoldEdgeCount: (map['nonManifoldEdgeCount'] as num?)?.toInt() ?? 0,
      connectedComponentCount: (map['connectedComponentCount'] as num?)?.toInt() ?? 0,
      degenerateTriangleCount: (map['degenerateTriangleCount'] as num?)?.toInt() ?? 0,
      surfaceArea: (map['surfaceArea'] as num?)?.toDouble() ?? 0,
      enclosedVolume: (map['enclosedVolume'] as num?)?.toDouble() ?? 0,
      closed: map['closed'] == true,
      unitKnown: map['unitKnown'] == true,
      unitLabel: (map['unitLabel'] as String?) ?? 'model-unit',
      boundsMin: vector('boundsMin'),
      boundsMax: vector('boundsMax'),
      size: vector('size'),
    );
  }
}

class NativeDocumentSummary {
  const NativeDocumentSummary({
    required this.handle,
    required this.sourcePath,
    required this.formatId,
    required this.triangleCount,
    required this.hasUv,
    required this.hasNormals,
    required this.exactGeometry,
    required this.rootObjectCount,
    required this.hierarchyNodeCount,
    required this.committed,
    required this.current,
  });

  final int handle;
  final String sourcePath;
  final String formatId;
  final int triangleCount;
  final bool hasUv;
  final bool hasNormals;
  final bool exactGeometry;
  final int rootObjectCount;
  final int hierarchyNodeCount;
  final bool committed;
  final bool current;

  factory NativeDocumentSummary.fromMap(Map<Object?, Object?> map) {
    return NativeDocumentSummary(
      handle: (map['handle'] as num).toInt(),
      sourcePath: (map['sourcePath'] as String?) ?? '',
      formatId: (map['formatId'] as String?) ?? 'unknown',
      triangleCount: (map['triangleCount'] as num?)?.toInt() ?? 0,
      hasUv: map['hasUv'] == true,
      hasNormals: map['hasNormals'] == true,
      exactGeometry: map['exactGeometry'] == true,
      rootObjectCount: (map['rootObjectCount'] as num?)?.toInt() ?? 0,
      hierarchyNodeCount: (map['hierarchyNodeCount'] as num?)?.toInt() ?? 0,
      committed: map['committed'] == true,
      current: map['current'] == true,
    );
  }
}

class CadObjectPresentation {
  const CadObjectPresentation({
    required this.id,
    required this.label,
    required this.type,
    required this.parentId,
    required this.visible,
    required this.effectiveVisible,
    required this.hasGeometry,
    required this.hasBaseColor,
    required this.baseColor,
  });

  final String id;
  final String label;
  final String type;
  final String parentId;
  final bool visible;
  final bool effectiveVisible;
  final bool hasGeometry;
  final bool hasBaseColor;
  final List<double> baseColor;

  bool get inheritedHidden => visible && !effectiveVisible;
  String get displayLabel => label.isEmpty ? id : label;

  factory CadObjectPresentation.fromMap(Map<String, dynamic> map) {
    final rawColor = (map['baseColor'] as List<dynamic>?) ?? const <dynamic>[];
    final color = rawColor
        .take(3)
        .map((value) => (value as num).toDouble())
        .toList(growable: false);
    return CadObjectPresentation(
      id: (map['id'] as String?) ?? '',
      label: (map['label'] as String?) ?? '',
      type: (map['type'] as String?) ?? '',
      parentId: (map['parentId'] as String?) ?? '',
      visible: map['visible'] == true,
      effectiveVisible: map['effectiveVisible'] == true,
      hasGeometry: map['hasGeometry'] == true,
      hasBaseColor: map['hasBaseColor'] == true,
      baseColor: color.length == 3 ? color : const <double>[0.70, 0.76, 0.84],
    );
  }

  static List<CadObjectPresentation> listFromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Object presentation payload is not a JSON array.');
    }
    return decoded
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Object presentation entry is not a JSON object.');
          }
          return CadObjectPresentation.fromMap(item);
        })
        .toList(growable: false);
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

  Future<CadMergeResult?> mergeDocuments() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('mergeDocuments');
    return raw == null ? null : CadMergeResult.fromMap(raw);
  }

  Future<CadExportResult?> exportCurrentModel(String formatId) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'exportCurrentModel',
      {'formatId': formatId},
    );
    return raw == null ? null : CadExportResult.fromMap(raw);
  }

  Future<CadSplitResult?> splitCurrentModel(String formatId) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'splitCurrentModel',
      {'formatId': formatId},
    );
    return raw == null ? null : CadSplitResult.fromMap(raw);
  }

  Future<MeshInspection> analyzeCurrentModel() async {
    final raw = await _channel.invokeMethod<String>('analyzeCurrentModel');
    if (raw == null || raw.isEmpty) {
      throw StateError('Native mesh inspection returned no result.');
    }
    return MeshInspection.fromJson(raw);
  }

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

  Future<List<CadObjectPresentation>> getObjectPresentation({int? handle}) async {
    final raw = await _channel.invokeMethod<String>(
      'getObjectPresentation',
      <String, Object?>{'handle': handle},
    );
    return CadObjectPresentation.listFromJson(raw ?? '[]');
  }

  Future<List<CadObjectPresentation>> setObjectVisibility({
    int? handle,
    required String objectId,
    required bool visible,
  }) async {
    final raw = await _channel.invokeMethod<String>(
      'setObjectVisibility',
      <String, Object?>{
        'handle': handle,
        'objectId': objectId,
        'visible': visible,
      },
    );
    return CadObjectPresentation.listFromJson(raw ?? '[]');
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
