import '../document/engineering_document.dart';

enum MergeMode { assembly, meshObject, booleanUnion, package }

enum SplitMode {
  connectedComponents,
  material,
  layer,
  assemblyChildren,
  solids,
  shells,
  selection,
}

class DocumentSelectionRef {
  const DocumentSelectionRef({
    required this.documentId,
    this.objectIds = const [],
  });

  final String documentId;
  final List<String> objectIds;
}

class MergeRequest {
  const MergeRequest({
    required this.mode,
    required this.sources,
    this.outputName = 'Combined',
    this.normalizeUnits = false,
    this.targetUnit,
  });

  final MergeMode mode;
  final List<DocumentSelectionRef> sources;
  final String outputName;
  final bool normalizeUnits;
  final String? targetUnit;
}

class SplitRequest {
  const SplitRequest({
    required this.mode,
    required this.source,
    this.keepRemainder = true,
  });

  final SplitMode mode;
  final DocumentSelectionRef source;
  final bool keepRemainder;
}

class CompositionAnalysis {
  const CompositionAnalysis({
    required this.available,
    this.warnings = const [],
    this.requiresUnitDecision = false,
    this.reason = '',
  });

  final bool available;
  final List<String> warnings;
  final bool requiresUnitDecision;
  final String reason;
}

class CompositionResult {
  const CompositionResult({
    required this.documents,
    required this.providerId,
    this.warnings = const [],
  });

  final List<EngineeringDocument> documents;
  final String providerId;
  final List<String> warnings;
}

abstract class CompositionProvider {
  String get id;

  CompositionAnalysis analyzeMerge(
    List<EngineeringDocument> documents,
    MergeRequest request,
  );

  CompositionAnalysis analyzeSplit(
    EngineeringDocument document,
    SplitRequest request,
  );

  Future<CompositionResult> merge(
    List<EngineeringDocument> documents,
    MergeRequest request,
  );

  Future<CompositionResult> split(
    EngineeringDocument document,
    SplitRequest request,
  );
}

class CompositionRegistry {
  final Map<String, CompositionProvider> _providers = {};

  Iterable<CompositionProvider> get providers => _providers.values;

  void register(CompositionProvider provider) {
    if (_providers.containsKey(provider.id)) {
      throw StateError('Composition provider already registered: ${provider.id}');
    }
    _providers[provider.id] = provider;
  }

  CompositionProvider? byId(String id) => _providers[id];
}
