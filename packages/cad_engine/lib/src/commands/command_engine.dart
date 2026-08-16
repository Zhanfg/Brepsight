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
    this.arguments = const [],
  });

  final String definitionId;
  final String rawText;
  final List<String> arguments;
}

class CommandParseResult {
  const CommandParseResult({
    required this.invocation,
    required this.definition,
  });

  final CommandInvocation invocation;
  final CommandDefinition definition;
}

class CommandResult {
  const CommandResult({
    required this.state,
    this.message = '',
  });

  final CommandExecutionState state;
  final String message;
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

class CommandParseException implements Exception {
  const CommandParseException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SimpleCommandParser {
  const SimpleCommandParser(this.registry);

  final CommandRegistry registry;

  CommandParseResult parse(String input) {
    final tokens = _tokenize(input);
    if (tokens.isEmpty) {
      throw const CommandParseException('请输入命令。');
    }
    final definition = registry.resolve(tokens.first);
    if (definition == null) {
      throw CommandParseException('未知命令：${tokens.first}');
    }
    final args = tokens.skip(1).toList(growable: false);
    final requiredCount = definition.arguments.where((item) => item.required).length;
    if (args.length < requiredCount) {
      final missing = definition.arguments[args.length].name;
      throw CommandParseException('${definition.name} 缺少参数：$missing');
    }
    if (args.length > definition.arguments.length) {
      throw CommandParseException('${definition.name} 参数过多。');
    }
    return CommandParseResult(
      definition: definition,
      invocation: CommandInvocation(
        definitionId: definition.id,
        rawText: input,
        arguments: args,
      ),
    );
  }

  List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    var escaping = false;

    void flush() {
      if (buffer.isEmpty) return;
      tokens.add(buffer.toString());
      buffer.clear();
    }

    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (escaping) {
        buffer.write(char);
        escaping = false;
        continue;
      }
      if (char == r'\') {
        escaping = true;
        continue;
      }
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          buffer.write(char);
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char.trim().isEmpty) {
        flush();
        continue;
      }
      buffer.write(char);
    }
    if (escaping) buffer.write(r'\');
    if (quote != null) {
      throw const CommandParseException('引号没有闭合。');
    }
    flush();
    return tokens;
  }
}
