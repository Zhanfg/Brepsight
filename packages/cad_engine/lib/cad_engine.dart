export 'src/document/conversion.dart';
export 'src/document/engineering_document.dart';
export 'src/document/importer.dart';
export 'src/document/pipeline.dart';
export 'src/document/writer.dart';
export 'src/format_catalog.dart';

import 'package:flutter/services.dart';

class CadLoadResult {
  const CadLoadResult({required this.ok, required this.displayName, required this.message});

  final bool ok;
  final String displayName;
  final String message;

  factory CadLoadResult.fromMap(Map<Object?, Object?> map) {
    return CadLoadResult(
      ok: map['ok'] == true,
      displayName: (map['displayName'] as String?) ?? '',
      message: (map['message'] as String?) ?? '',
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
