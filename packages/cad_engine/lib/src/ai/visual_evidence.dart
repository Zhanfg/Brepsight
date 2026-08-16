enum VisualEvidenceSourceKind {
  referencePhoto,
  sketch,
  engineeringDrawing,
  screenshot,
  renderedView,
  scanPreview,
  textureReference,
}

enum VisualEvidenceKind {
  object,
  feature,
  text,
  dimension,
  symbol,
  materialCue,
  surfaceCue,
  topologyCue,
  alignmentCue,
  discrepancy,
}

class NormalizedRect {
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

class VisualEvidenceItem {
  const VisualEvidenceItem({
    required this.kind,
    required this.label,
    required this.confidence,
    this.value,
    this.unit,
    this.region,
    this.notes = const [],
  });

  final VisualEvidenceKind kind;
  final String label;
  final double confidence;
  final String? value;
  final String? unit;
  final NormalizedRect? region;
  final List<String> notes;
}

class VisualEvidence {
  const VisualEvidence({
    required this.sourceKind,
    required this.providerId,
    required this.items,
    required this.summary,
    this.sourcePath,
    this.viewName,
    this.warnings = const [],
    this.offline = false,
  });

  final VisualEvidenceSourceKind sourceKind;
  final String providerId;
  final List<VisualEvidenceItem> items;
  final String summary;
  final String? sourcePath;
  final String? viewName;
  final List<String> warnings;
  final bool offline;
}

class VisionBridgeRequest {
  const VisionBridgeRequest({
    required this.sourceKind,
    required this.imagePath,
    required this.task,
    this.maxResolution,
    this.expectedUnits,
    this.referenceEvidence,
  });

  final VisualEvidenceSourceKind sourceKind;
  final String imagePath;
  final String task;
  final int? maxResolution;
  final String? expectedUnits;
  final VisualEvidence? referenceEvidence;
}

abstract class VisionBridgeProvider {
  String get id;

  /// True only when the provider can run without a network dependency.
  bool get supportsOffline;

  /// Converts pixels into compact, structured evidence for a text-only CAD agent.
  Future<VisualEvidence> inspect(VisionBridgeRequest request);
}

class VisualValidationReport {
  const VisualValidationReport({
    required this.reference,
    required this.rendered,
    required this.score,
    required this.discrepancies,
    this.warnings = const [],
  });

  final VisualEvidence reference;
  final VisualEvidence rendered;
  final double score;
  final List<VisualEvidenceItem> discrepancies;
  final List<String> warnings;
}

/// Visual validation is advisory. Exact dimensions, topology and B-Rep/solid
/// validity must still be checked by deterministic engineering validators.
abstract class VisualCadValidator {
  Future<VisualValidationReport> compare({
    required VisualEvidence reference,
    required VisualEvidence rendered,
  });
}
