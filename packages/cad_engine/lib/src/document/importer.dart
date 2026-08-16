import 'dart:typed_data';

import 'engineering_document.dart';

class ImportRequest {
  const ImportRequest({
    required this.path,
    required this.extension,
    this.header,
  });

  final String path;
  final String extension;
  final Uint8List? header;
}

class ImportProbe {
  const ImportProbe({
    required this.score,
    required this.formatId,
    this.reason = '',
  });

  /// 0 = cannot handle; 100 = exact/authoritative match.
  final int score;
  final String formatId;
  final String reason;
}

abstract class EngineeringImporter {
  String get id;
  Set<String> get supportedFormatIds;

  Future<ImportProbe> probe(ImportRequest request);
  Future<EngineeringDocument> importDocument(ImportRequest request);
}

class ImportResolution {
  const ImportResolution({required this.importer, required this.probe});

  final EngineeringImporter importer;
  final ImportProbe probe;
}

class ImporterRegistry {
  final Map<String, EngineeringImporter> _importers = {};

  Iterable<EngineeringImporter> get importers => _importers.values;

  void register(EngineeringImporter importer) {
    if (_importers.containsKey(importer.id)) {
      throw StateError('Importer id already registered: ${importer.id}');
    }
    _importers[importer.id] = importer;
  }

  EngineeringImporter? byId(String id) => _importers[id];

  Future<ImportResolution?> resolve(ImportRequest request) async {
    ImportResolution? best;
    for (final importer in _importers.values) {
      final probe = await importer.probe(request);
      if (probe.score <= 0) continue;
      if (best == null || probe.score > best.probe.score) {
        best = ImportResolution(importer: importer, probe: probe);
      }
    }
    return best;
  }
}
