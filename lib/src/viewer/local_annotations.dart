import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class LocalModelAnnotation {
  const LocalModelAnnotation({
    required this.id,
    required this.text,
    required this.createdAtMillis,
    this.anchorKind,
    this.featureStableId,
    this.triangleIndex = -1,
    this.featureIndex = -1,
    this.objectIndex = -1,
    this.x,
    this.y,
    this.z,
    this.depth,
    this.screenshotPngBase64,
  });

  final String id;
  final String text;
  final int createdAtMillis;
  final String? anchorKind;
  final String? featureStableId;
  final int triangleIndex;
  final int featureIndex;
  final int objectIndex;
  final double? x;
  final double? y;
  final double? z;
  final double? depth;
  final String? screenshotPngBase64;

  bool get hasAnchor =>
      featureStableId != null &&
      featureStableId!.isNotEmpty &&
      triangleIndex >= 0 &&
      x != null &&
      y != null &&
      z != null &&
      depth != null;

  bool get hasScreenshot =>
      screenshotPngBase64 != null && screenshotPngBase64!.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'text': text,
        'createdAtMillis': createdAtMillis,
        if (anchorKind != null) 'anchorKind': anchorKind,
        if (featureStableId != null) 'featureStableId': featureStableId,
        'triangleIndex': triangleIndex,
        'featureIndex': featureIndex,
        'objectIndex': objectIndex,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (z != null) 'z': z,
        if (depth != null) 'depth': depth,
        if (screenshotPngBase64 != null)
          'screenshotPngBase64': screenshotPngBase64,
      };

  factory LocalModelAnnotation.fromJson(Map<String, dynamic> map) {
    final id = map['id'];
    final text = map['text'];
    final createdAtMillis = map['createdAtMillis'];
    if (id is! String || id.isEmpty || text is! String || createdAtMillis is! num) {
      throw const FormatException('Invalid local annotation payload.');
    }
    double? optionalDouble(String key) {
      final value = map[key];
      return value is num ? value.toDouble() : null;
    }

    return LocalModelAnnotation(
      id: id,
      text: text,
      createdAtMillis: createdAtMillis.toInt(),
      anchorKind: map['anchorKind'] as String?,
      featureStableId: map['featureStableId'] as String?,
      triangleIndex: (map['triangleIndex'] as num?)?.toInt() ?? -1,
      featureIndex: (map['featureIndex'] as num?)?.toInt() ?? -1,
      objectIndex: (map['objectIndex'] as num?)?.toInt() ?? -1,
      x: optionalDouble('x'),
      y: optionalDouble('y'),
      z: optionalDouble('z'),
      depth: optionalDouble('depth'),
      screenshotPngBase64: map['screenshotPngBase64'] as String?,
    );
  }

  static String encodeList(List<LocalModelAnnotation> annotations) =>
      jsonEncode(annotations.map((item) => item.toJson()).toList(growable: false));

  static List<LocalModelAnnotation> decodeList(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Annotation store root must be a JSON list.');
    }
    final result = <LocalModelAnnotation>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      try {
        result.add(LocalModelAnnotation.fromJson(item));
      } on FormatException {
        // A damaged row must not make every annotation for the model unreadable.
      }
    }
    result.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return result;
  }
}

class ModelAnnotationIdentity {
  static final BigInt _fnvOffset =
      BigInt.parse('cbf29ce484222325', radix: 16);
  static final BigInt _fnvPrime = BigInt.parse('100000001b3', radix: 16);
  static final BigInt _mask64 =
      BigInt.parse('ffffffffffffffff', radix: 16);
  static const int _sampleBytes = 64 * 1024;

  static Future<String> forModel({
    required String sourcePath,
    required String formatId,
    required int triangleCount,
    required int rootObjectCount,
    required int hierarchyNodeCount,
  }) async {
    var hash = _fnvOffset;
    hash = _update(hash, utf8.encode(
      '${File(sourcePath).uri.pathSegments.lastOrNull ?? sourcePath}|'
      '${formatId.toLowerCase()}|$triangleCount|$rootObjectCount|$hierarchyNodeCount|',
    ));

    try {
      final file = File(sourcePath);
      final length = await file.length();
      hash = _update(hash, utf8.encode('size:$length|'));
      final handle = await file.open();
      try {
        final maxStart = length > _sampleBytes ? length - _sampleBytes : 0;
        final offsets = <int>{
          0,
          (length ~/ 2 - _sampleBytes ~/ 2).clamp(0, maxStart).toInt(),
          maxStart,
        }.toList(growable: false)
          ..sort();
        for (final offset in offsets) {
          await handle.setPosition(offset);
          final remaining = length - offset;
          final count = remaining.clamp(0, _sampleBytes).toInt();
          if (count > 0) hash = _update(hash, await handle.read(count));
        }
      } finally {
        await handle.close();
      }
    } on FileSystemException {
      // Some provider-backed paths may not be stat-able later. Metadata and
      // stable display name still provide a deterministic local fallback key.
      hash = _update(hash, utf8.encode('file-unavailable'));
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }

  static BigInt _update(BigInt hash, Iterable<int> bytes) {
    var value = hash;
    for (final byte in bytes) {
      value ^= BigInt.from(byte & 0xff);
      value = (value * _fnvPrime) & _mask64;
    }
    return value;
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

class LocalAnnotationStore {
  LocalAnnotationStore._();

  static final LocalAnnotationStore instance = LocalAnnotationStore._();
  static const _prefix = 'viewer.annotations.v1.';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<List<LocalModelAnnotation>> load(String modelKey) async {
    final raw = await _preferences.getString('$_prefix$modelKey');
    if (raw == null || raw.isEmpty) return const <LocalModelAnnotation>[];
    try {
      return LocalModelAnnotation.decodeList(raw);
    } on FormatException {
      return const <LocalModelAnnotation>[];
    }
  }

  Future<void> save(
    String modelKey,
    List<LocalModelAnnotation> annotations,
  ) async {
    final key = '$_prefix$modelKey';
    if (annotations.isEmpty) {
      await _preferences.remove(key);
      return;
    }
    await _preferences.setString(key, LocalModelAnnotation.encodeList(annotations));
  }
}
