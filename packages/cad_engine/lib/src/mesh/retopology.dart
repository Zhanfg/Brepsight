import '../document/engineering_document.dart';

enum RetopologyUseCase {
  generalModeling,
  subdivision,
  sculpting,
  hardSurface,
  animationAssist,
  reverseEngineering,
}

enum RetopologyTopologyTarget {
  quadDominant,
  allQuads,
}

enum SymmetryAxis { x, y, z }

class RetopologyRequest {
  const RetopologyRequest({
    required this.useCase,
    this.topologyTarget = RetopologyTopologyTarget.quadDominant,
    this.targetFaceCount,
    this.targetRatio,
    this.preserveBoundary = true,
    this.preserveSharpFeatures = true,
    this.projectToSource = true,
    this.transferUv = true,
    this.transferNormals = true,
    this.transferVertexColors = true,
    this.transferMaterials = true,
    this.symmetryAxis,
  }) : assert(targetFaceCount == null || targetFaceCount > 0),
       assert(targetRatio == null || (targetRatio > 0 && targetRatio <= 1)),
       assert(targetFaceCount == null || targetRatio == null,
           'Use targetFaceCount or targetRatio, not both.');

  final RetopologyUseCase useCase;
  final RetopologyTopologyTarget topologyTarget;
  final int? targetFaceCount;
  final double? targetRatio;
  final bool preserveBoundary;
  final bool preserveSharpFeatures;
  final bool projectToSource;
  final bool transferUv;
  final bool transferNormals;
  final bool transferVertexColors;
  final bool transferMaterials;
  final SymmetryAxis? symmetryAxis;
}

class RetopologyProviderProfile {
  const RetopologyProviderProfile({
    required this.supportsQuadDominant,
    required this.supportsAllQuads,
    required this.supportsBoundaryPreservation,
    required this.supportsSharpPreservation,
    required this.supportsSymmetry,
    required this.supportsAttributeTransfer,
    required this.supportsInteractiveGuides,
  });

  final bool supportsQuadDominant;
  final bool supportsAllQuads;
  final bool supportsBoundaryPreservation;
  final bool supportsSharpPreservation;
  final bool supportsSymmetry;
  final bool supportsAttributeTransfer;
  final bool supportsInteractiveGuides;
}

class RetopologyQualityReport {
  const RetopologyQualityReport({
    required this.inputFaceCount,
    required this.outputFaceCount,
    required this.quadCount,
    required this.triangleCount,
    required this.ngonCount,
    this.meanSurfaceDeviation,
    this.maxSurfaceDeviation,
    this.isManifold,
    this.boundaryPreserved,
    this.warnings = const [],
  });

  final int inputFaceCount;
  final int outputFaceCount;
  final int quadCount;
  final int triangleCount;
  final int ngonCount;
  final double? meanSurfaceDeviation;
  final double? maxSurfaceDeviation;
  final bool? isManifold;
  final bool? boundaryPreserved;
  final List<String> warnings;

  double get quadRatio => outputFaceCount == 0 ? 0 : quadCount / outputFaceCount;
}

class RetopologyAnalysis {
  const RetopologyAnalysis({
    required this.available,
    required this.providerId,
    required this.warnings,
    this.reason = '',
  });

  final bool available;
  final String providerId;
  final List<String> warnings;
  final String reason;
}

class RetopologyResult {
  const RetopologyResult({
    required this.document,
    required this.report,
    required this.providerId,
  });

  final EngineeringDocument document;
  final RetopologyQualityReport report;
  final String providerId;
}

abstract class RetopologyProvider {
  String get id;
  RetopologyProviderProfile get profile;

  RetopologyAnalysis analyze(
    EngineeringDocument document,
    RetopologyRequest request,
  );

  Future<RetopologyResult> retopologize(
    EngineeringDocument document,
    RetopologyRequest request,
  );
}

class RetopologyRegistry {
  final Map<String, RetopologyProvider> _providers = {};

  Iterable<RetopologyProvider> get providers => _providers.values;

  void register(RetopologyProvider provider) {
    if (_providers.containsKey(provider.id)) {
      throw StateError('Retopology provider id already registered: ${provider.id}');
    }
    _providers[provider.id] = provider;
  }

  RetopologyProvider? byId(String id) => _providers[id];

  Iterable<RetopologyAnalysis> analyzeAll(
    EngineeringDocument document,
    RetopologyRequest request,
  ) => _providers.values.map((provider) => provider.analyze(document, request));
}
