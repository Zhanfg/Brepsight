enum CommandInputKind { none, text, number, point, object, face, edge, selection }

enum CommandExecutionState { ready, awaitingInput, runningTask, completed, failed, cancelled }

class CommandArgumentSpec {
  const CommandArgumentSpec({
    required this.name,
    required this.kind,
    this.required = true,
    this.unitAware = false,
    this.description = '',
  });

  final String name;
  final CommandInputKind kind;
  final bool required;
  final bool unitAware;
  final String description;
}

class CommandDefinition {
  const CommandDefinition({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.arguments = const [],
    this.description = '',
    this.longRunning = false,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final List<CommandArgumentSpec> arguments;
  final String description;
  final bool longRunning;
}

class CommandInvocation {
  const CommandInvocation({
    required this.definitionId,
    required this.rawText,
    this.arguments = const {},
    this.references = const [],
  });

  final String definitionId;
  final String rawText;
  final Map<String, Object?> arguments;
  final List<String> references;
}

class CommandPrompt {
  const CommandPrompt({
    required this.message,
    required this.kind,
    this.options = const [],
  });

  final String message;
  final CommandInputKind kind;
  final List<String> options;
}

class CommandResult {
  const CommandResult({
    required this.state,
    this.message = '',
    this.taskId,
    this.transactionId,
    this.prompt,
  });

  final CommandExecutionState state;
  final String message;
  final String? taskId;
  final String? transactionId;
  final CommandPrompt? prompt;
}

abstract class CommandParser {
  CommandInvocation parse(String text);
}

abstract class CommandExecutor {
  Future<CommandResult> execute(CommandInvocation invocation);
  Future<CommandResult> provideInput(String invocationId, Object? value);
  Future<void> cancel(String invocationId);
}

class CommandRegistry {
  final Map<String, CommandDefinition> _definitions = {};
  final Map<String, String> _lookup = {};

  Iterable<CommandDefinition> get definitions => _definitions.values;

  void register(CommandDefinition definition) {
    if (_definitions.containsKey(definition.id)) {
      throw StateError('Command already registered: ${definition.id}');
    }
    _definitions[definition.id] = definition;
    _bind(definition.name, definition.id);
    for (final alias in definition.aliases) {
      _bind(alias, definition.id);
    }
  }

  CommandDefinition? resolve(String token) {
    final id = _lookup[token.trim().toLowerCase()];
    return id == null ? null : _definitions[id];
  }

  Iterable<CommandDefinition> suggest(String prefix) {
    final normalized = prefix.trim().toLowerCase();
    if (normalized.isEmpty) return definitions;
    final ids = <String>{};
    for (final entry in _lookup.entries) {
      if (entry.key.startsWith(normalized)) ids.add(entry.value);
    }
    return ids.map((id) => _definitions[id]!).toList(growable: false);
  }

  void _bind(String token, String id) {
    final key = token.trim().toLowerCase();
    if (key.isEmpty) return;
    final existing = _lookup[key];
    if (existing != null && existing != id) {
      throw StateError('Command token already bound: $token');
    }
    _lookup[key] = id;
  }
}
