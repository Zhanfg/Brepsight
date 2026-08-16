import 'package:brepsight/src/viewer/viewer_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('viewer registry exposes only currently wired commands', () {
    final registry = createViewerCommandRegistry();

    expect(registry.resolve('F')?.id, 'view.fit');
    expect(registry.resolve('INSPECT')?.id, 'document.inspect');
    expect(registry.resolve('EX')?.id, 'document.export');
    expect(registry.resolve('SP')?.id, 'document.split');
    expect(registry.resolve('?')?.id, 'help');

    expect(registry.resolve('FILLET'), isNull);
    expect(registry.resolve('BOOLEAN'), isNull);
    expect(registry.resolve('ORTHO'), isNull);
  });
}
