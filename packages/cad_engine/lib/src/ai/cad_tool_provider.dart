import '../document/engineering_document.dart';

class CadObjectRef {
  const CadObjectRef({required this.documentId, required this.objectId, this.featureId});

  final String documentId;
  final String objectId;
  final String? featureId;
}

enum CadToolMutationKind { readOnly, mutating, longRunning }

class CadToolDefinition {
  const CadToolDefinition({
    required this.name,
    required this.description,
    required this.mutationKind,
    this.requiredCapabilities = const {},
  });

  final String name;
  final String description;
  final CadToolMutationKind mutationKind;
  final Set<DocumentCapability> requiredCapabilities;
}

class CadToolInvocation {
  const CadToolInvocation({
    required this.tool,
    this.arguments = const {},
    this.targets = const [],
  });

  final String tool;
  final Map<String, Object?> arguments;
  final List<CadObjectRef> targets;
}

class CadToolResult {
  const CadToolResult({
    required this.ok,
    required this.message,
    this.document,
    this.references = const [],
    this.measurements = const {},
    this.warnings = const [],
    this.taskId,
  });

  final bool ok;
  final String message;
  final EngineeringDocument? document;
  final List<CadObjectRef> references;
  final Map<String, num> measurements;
  final List<String> warnings;
  final String? taskId;
}

abstract class CadToolSession {
  EngineeringDocument get document;
  Iterable<CadToolDefinition> get tools;

  Future<CadToolResult> inspect(CadObjectRef reference);
  Future<CadToolResult> invoke(CadToolInvocation invocation);
  Future<CadToolResult> validate();
  Future<void> discard();
  Future<EngineeringDocument> commit();
}

abstract class CadToolProvider {
  String get id;
  String get displayName;
  bool get supportsOffline;
  bool get supportsLocalExecution;

  Future<bool> isAvailable();
  Future<CadToolSession> openSession(EngineeringDocument document);
}
