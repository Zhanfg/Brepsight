import 'dart:math' as math;

import 'package:flutter/services.dart';

class CadImportProgress {
  const CadImportProgress({
    required this.active,
    required this.taskId,
    required this.path,
    required this.stage,
    required this.progress,
    required this.cancelRequested,
  });

  final bool active;
  final int taskId;
  final String path;
  final String stage;
  final int progress;
  final bool cancelRequested;

  factory CadImportProgress.fromMap(Map<Object?, Object?> map) =>
      CadImportProgress(
        active: map['active'] == true,
        taskId: (map['taskId'] as num?)?.toInt() ?? 0,
        path: (map['path'] as String?) ?? '',
        stage: (map['stage'] as String?) ?? 'idle',
        progress: ((map['progress'] as num?)?.toInt() ?? 0)
            .clamp(0, 100)
            .toInt(),
        cancelRequested: map['cancelRequested'] == true,
      );
}

enum CadSnapKind {
  free,
  vertex,
  edgeMidpoint,
  faceCenter;

  static CadSnapKind fromNativeCode(int code) =>
      code >= 0 && code < values.length ? values[code] : CadSnapKind.free;
}

enum CadSelectionFilter { vertex, edge, face, body }

class CadPickPoint {
  const CadPickPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.triangleIndex,
    required this.depth,
    required this.documentHandle,
    this.snapKind = CadSnapKind.free,
    this.featureIndex = -1,
    this.objectIndex = -1,
  });

  final double x;
  final double y;
  final double z;
  final int triangleIndex;
  final double depth;
  final int documentHandle;
  final CadSnapKind snapKind;
  final int featureIndex;
  final int objectIndex;

  String get stableId => '$documentHandle:$triangleIndex';
  String get featureStableId =>
      '$documentHandle:$triangleIndex:${snapKind.name}:$featureIndex';

  List<double> get xyz => <double>[x, y, z];

  factory CadPickPoint.fromList(List<Object?> raw, int handle) {
    if (raw.length < 5) {
      throw const FormatException('Native pick payload is incomplete.');
    }
    return CadPickPoint(
      x: (raw[0] as num).toDouble(),
      y: (raw[1] as num).toDouble(),
      z: (raw[2] as num).toDouble(),
      triangleIndex: (raw[3] as num).toInt(),
      depth: (raw[4] as num).toDouble(),
      documentHandle: handle,
      snapKind: raw.length >= 6
          ? CadSnapKind.fromNativeCode((raw[5] as num).toInt())
          : CadSnapKind.free,
      featureIndex: raw.length >= 7 ? (raw[6] as num).toInt() : -1,
      objectIndex: raw.length >= 8 ? (raw[7] as num).toInt() : -1,
    );
  }
}

enum CadMeasurementMode { none, distance, angle, radius }

class CadMeasurement {
  CadMeasurement._();

  static double distance(CadPickPoint a, CadPickPoint b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final dz = b.z - a.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Angle ABC in degrees.
  static double? angle(CadPickPoint a, CadPickPoint b, CadPickPoint c) {
    final bax = a.x - b.x;
    final bay = a.y - b.y;
    final baz = a.z - b.z;
    final bcx = c.x - b.x;
    final bcy = c.y - b.y;
    final bcz = c.z - b.z;
    final ba = math.sqrt(bax * bax + bay * bay + baz * baz);
    final bc = math.sqrt(bcx * bcx + bcy * bcy + bcz * bcz);
    if (ba <= 1e-12 || bc <= 1e-12) return null;
    final cosine = ((bax * bcx + bay * bcy + baz * bcz) / (ba * bc))
        .clamp(-1.0, 1.0)
        .toDouble();
    return math.acos(cosine) * 180.0 / math.pi;
  }

  /// Circumradius through three picked points. Returns null for collinear or
  /// coincident points.
  static double? radius(CadPickPoint a, CadPickPoint b, CadPickPoint c) {
    final ab = distance(a, b);
    final bc = distance(b, c);
    final ca = distance(c, a);
    if (ab <= 1e-12 || bc <= 1e-12 || ca <= 1e-12) return null;

    final twiceArea = _twiceTriangleArea(a, b, c);
    if (twiceArea <= 1e-12) return null;
    return (ab * bc * ca) / (2.0 * twiceArea);
  }

  /// 3D area of triangle ABC in model units squared. The three points may lie
  /// on any plane in world space; no XY projection is used.
  static double area(CadPickPoint a, CadPickPoint b, CadPickPoint c) =>
      _twiceTriangleArea(a, b, c) * 0.5;

  static double _twiceTriangleArea(
    CadPickPoint a,
    CadPickPoint b,
    CadPickPoint c,
  ) {
    final ux = b.x - a.x;
    final uy = b.y - a.y;
    final uz = b.z - a.z;
    final vx = c.x - a.x;
    final vy = c.y - a.y;
    final vz = c.z - a.z;
    final cx = uy * vz - uz * vy;
    final cy = uz * vx - ux * vz;
    final cz = ux * vy - uy * vx;
    return math.sqrt(cx * cx + cy * cy + cz * cz);
  }
}

class CadEngineV01Tools {
  CadEngineV01Tools._();

  static final CadEngineV01Tools instance = CadEngineV01Tools._();
  static const MethodChannel _channel = MethodChannel('cad_engine/methods');

  Future<CadImportProgress> importProgress() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getImportProgress',
    );
    return CadImportProgress.fromMap(raw ?? const <Object?, Object?>{});
  }

  Future<bool> cancelImport() async =>
      await _channel.invokeMethod<bool>('cancelImport') ?? false;

  Future<CadPickPoint?> pickModelPoint({
    required int documentHandle,
    required int width,
    required int height,
    required double orbitX,
    required double orbitY,
    required double panX,
    required double panY,
    required double zoom,
    required bool orthographic,
    required double screenX,
    required double screenY,
  }) async {
    final raw = await _channel
        .invokeMethod<List<Object?>>('pickModelPoint', <String, Object?>{
          'handle': documentHandle,
          'width': width,
          'height': height,
          'orbitX': orbitX,
          'orbitY': orbitY,
          'panX': panX,
          'panY': panY,
          'zoom': zoom,
          'orthographic': orthographic,
          'screenX': screenX,
          'screenY': screenY,
        });
    return raw == null ? null : CadPickPoint.fromList(raw, documentHandle);
  }

  Future<void> setSelectionHighlight({
    required CadSelectionFilter filter,
    required CadPickPoint point,
  }) {
    final kind = switch (filter) {
      CadSelectionFilter.vertex => 1,
      CadSelectionFilter.edge => 2,
      CadSelectionFilter.face => 3,
      CadSelectionFilter.body => 4,
    };
    return _channel.invokeMethod<void>('setDisplayMode', <String, Object?>{
      'mode': 'selection:$kind:${point.triangleIndex}:${point.featureIndex}',
    });
  }

  Future<void> clearSelectionHighlight() => _channel.invokeMethod<void>(
    'setDisplayMode',
    const <String, Object?>{'mode': 'selection_clear'},
  );

  Future<void> setExplodeFactor(double factor) {
    final safe = factor.clamp(0.0, 1.0).toDouble();
    return _channel.invokeMethod<void>('setDisplayMode', <String, Object?>{
      'mode': 'explode:${safe.toStringAsFixed(4)}',
    });
  }

  Future<bool> setSectionPlane({
    required bool enabled,
    double nx = 0,
    double ny = 0,
    double nz = 1,
    double offset = 0,
  }) async =>
      await _channel.invokeMethod<bool>('setSectionPlane', <String, Object?>{
        'enabled': enabled,
        'nx': nx,
        'ny': ny,
        'nz': nz,
        'offset': offset,
      }) ??
      false;
}
