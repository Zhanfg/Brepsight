import 'package:cad_engine/cad_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MeshEditState parses native working-copy contract', () {
    final state = MeshEditState.fromMap(<Object?, Object?>{
      'active': true,
      'busy': false,
      'canUndo': true,
      'canRedo': false,
      'cursor': 2,
      'revisionCount': 3,
      'currentHandle': 42,
      'sourcePath': '/source/model.step',
      'sourceFormatId': 'step',
      'workingCopyPath': '/cache/edit_0002.obj',
      'meshWorkingCopy': true,
      'sourceOverwritten': false,
    });

    expect(state.active, isTrue);
    expect(state.busy, isFalse);
    expect(state.canUndo, isTrue);
    expect(state.canRedo, isFalse);
    expect(state.cursor, 2);
    expect(state.revisionCount, 3);
    expect(state.currentHandle, 42);
    expect(state.sourceFormatId, 'step');
    expect(state.meshWorkingCopy, isTrue);
    expect(state.sourceOverwritten, isFalse);
  });

  test('inactive state uses conservative defaults', () {
    final state = MeshEditState.fromMap(const <Object?, Object?>{});
    expect(state.active, isFalse);
    expect(state.canUndo, isFalse);
    expect(state.canRedo, isFalse);
    expect(state.cursor, -1);
    expect(state.currentHandle, 0);
    expect(state.sourceOverwritten, isFalse);
  });
}
