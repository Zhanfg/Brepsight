import 'engineering_document.dart';

enum CapabilityDisposition {
  preserved,
  degraded,
  lost,
  notApplicable,
}

class CapabilityImpact {
  const CapabilityImpact({
    required this.capability,
    required this.disposition,
    this.message = '',
  });

  final DocumentCapability capability;
  final CapabilityDisposition disposition;
  final String message;
}

class ExportAnalysis {
  const ExportAnalysis({
    required this.canExport,
    required this.outputFormatId,
    required this.impacts,
    this.reason = '',
  });

  final bool canExport;
  final String outputFormatId;
  final List<CapabilityImpact> impacts;
  final String reason;

  int get preservedCount => impacts
      .where((impact) => impact.disposition == CapabilityDisposition.preserved)
      .length;

  int get degradedCount => impacts
      .where((impact) => impact.disposition == CapabilityDisposition.degraded)
      .length;

  int get lostCount => impacts
      .where((impact) => impact.disposition == CapabilityDisposition.lost)
      .length;
}

class ExportResult {
  const ExportResult({
    required this.ok,
    required this.outputPath,
    required this.outputFormatId,
    this.message = '',
  });

  final bool ok;
  final String outputPath;
  final String outputFormatId;
  final String message;
}

abstract class EngineeringWriter {
  String get id;
  String get outputFormatId;

  ExportAnalysis analyze(EngineeringDocument document);

  Future<ExportResult> exportDocument(
    EngineeringDocument document, {
    required String outputPath,
  });
}

/// Base class for format writers whose semantic limits are known declaratively.
///
/// Concrete writers still implement [exportDocument], but they do not need to
/// reinvent loss reporting. Any source capability not explicitly preserved or
/// degraded is reported as lost.
abstract class ProfiledEngineeringWriter extends EngineeringWriter {
  Set<EngineeringRepresentation> get supportedRepresentations;
  Set<DocumentCapability> get preservedCapabilities;
  Set<DocumentCapability> get degradedCapabilities => const {};

  @override
  ExportAnalysis analyze(EngineeringDocument document) {
    final hasSupportedRepresentation = document.representations.any(
      supportedRepresentations.contains,
    );
    if (!hasSupportedRepresentation) {
      return ExportAnalysis(
        canExport: false,
        outputFormatId: outputFormatId,
        impacts: const [],
        reason: 'Writer $id cannot consume the document representations.',
      );
    }

    final impacts = <CapabilityImpact>[];
    for (final capability in document.capabilities.values) {
      final disposition = preservedCapabilities.contains(capability)
          ? CapabilityDisposition.preserved
          : degradedCapabilities.contains(capability)
              ? CapabilityDisposition.degraded
              : CapabilityDisposition.lost;
      impacts.add(
        CapabilityImpact(
          capability: capability,
          disposition: disposition,
          message: impactMessage(capability, disposition),
        ),
      );
    }

    return ExportAnalysis(
      canExport: true,
      outputFormatId: outputFormatId,
      impacts: List.unmodifiable(impacts),
    );
  }

  String impactMessage(
    DocumentCapability capability,
    CapabilityDisposition disposition,
  ) =>
      '';
}

class WriterRegistry {
  final Map<String, EngineeringWriter> _writers = {};

  Iterable<EngineeringWriter> get writers => _writers.values;

  void register(EngineeringWriter writer) {
    if (_writers.containsKey(writer.id)) {
      throw StateError('Writer id already registered: ${writer.id}');
    }
    _writers[writer.id] = writer;
  }

  EngineeringWriter? byId(String id) => _writers[id];

  Iterable<EngineeringWriter> forFormat(String formatId) =>
      _writers.values.where((writer) => writer.outputFormatId == formatId);
}
