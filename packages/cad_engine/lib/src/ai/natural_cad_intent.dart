import 'cad_tool_provider.dart';

enum NaturalCadIntentKind {
  create,
  edit,
  query,
  select,
  transform,
  repair,
  compose,
  convert,
  validate,
  simulate,
}

enum CadReferenceSource {
  explicitSelection,
  stableId,
  namedFeature,
  geometryPredicate,
  visualCandidate,
}

class CadReferenceBinding {
  const CadReferenceBinding({
    required this.phrase,
    required this.source,
    this.candidates = const [],
    this.resolved,
    this.confidence = 0,
    this.requiresUserBinding = false,
  });

  final String phrase;
  final CadReferenceSource source;
  final List<CadObjectRef> candidates;
  final CadObjectRef? resolved;
  final double confidence;
  final bool requiresUserBinding;
}

class CadEditStep {
  const CadEditStep({
    required this.id,
    required this.invocation,
    this.reason = '',
    this.expectedEffects = const [],
    this.preservedProperties = const [],
  });

  final String id;
  final CadToolInvocation invocation;
  final String reason;
  final List<String> expectedEffects;
  final List<String> preservedProperties;
}

class CadEditPlan {
  const CadEditPlan({
    required this.intent,
    required this.summary,
    this.bindings = const [],
    this.steps = const [],
    this.validationRules = const [],
    this.warnings = const [],
  });

  final NaturalCadIntentKind intent;
  final String summary;
  final List<CadReferenceBinding> bindings;
  final List<CadEditStep> steps;
  final List<String> validationRules;
  final List<String> warnings;

  bool get isReady =>
      bindings.every((binding) => !binding.requiresUserBinding && binding.resolved != null) ||
      bindings.isEmpty;
}

class CadSemanticChange {
  const CadSemanticChange({
    required this.target,
    required this.property,
    this.before,
    this.after,
    this.unit,
  });

  final CadObjectRef target;
  final String property;
  final Object? before;
  final Object? after;
  final String? unit;
}

class CadEditPreview {
  const CadEditPreview({
    required this.plan,
    this.changes = const [],
    this.validationMessages = const [],
    this.warnings = const [],
    this.valid = false,
  });

  final CadEditPlan plan;
  final List<CadSemanticChange> changes;
  final List<String> validationMessages;
  final List<String> warnings;
  final bool valid;
}

abstract class NaturalCadIntentProvider {
  String get id;
  String get displayName;
  bool get supportsOffline;

  Future<CadEditPlan> plan({
    required String request,
    required CadToolSession session,
    List<CadObjectRef> explicitSelection = const [],
  });
}

abstract class CadEditCoordinator {
  Future<CadEditPreview> preview(CadEditPlan plan, CadToolSession session);
  Future<CadToolResult> commit(CadEditPreview preview, CadToolSession session);
  Future<void> discard(CadEditPreview preview, CadToolSession session);
}
