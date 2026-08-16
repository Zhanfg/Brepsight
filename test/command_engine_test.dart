import 'package:cad_engine/cad_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CommandRegistry registry;
  late SimpleCommandParser parser;

  setUp(() {
    registry = CommandRegistry()
      ..register(const CommandDefinition(
        id: 'view.fit',
        name: 'FIT',
        aliases: ['F'],
      ))
      ..register(const CommandDefinition(
        id: 'export',
        name: 'EXPORT',
        aliases: ['EX'],
        arguments: [
          CommandArgumentSpec(name: 'format', kind: CommandInputKind.text),
        ],
      ));
    parser = SimpleCommandParser(registry);
  });

  test('resolves aliases case-insensitively', () {
    final parsed = parser.parse('f');
    expect(parsed.definition.id, 'view.fit');
    expect(parsed.invocation.arguments, isEmpty);
  });

  test('tokenizes quoted arguments deterministically', () {
    final parsed = parser.parse('EXPORT "obj"');
    expect(parsed.definition.id, 'export');
    expect(parsed.invocation.arguments, ['obj']);
  });

  test('rejects missing required argument', () {
    expect(
      () => parser.parse('EXPORT'),
      throwsA(isA<CommandParseException>()),
    );
  });

  test('rejects unknown command instead of forwarding it', () {
    expect(
      () => parser.parse('rm -rf /'),
      throwsA(isA<CommandParseException>()),
    );
  });
}
