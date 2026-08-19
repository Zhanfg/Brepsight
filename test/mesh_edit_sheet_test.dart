import 'package:brepsight/src/viewer/mesh_edit_sheet.dart';
import 'package:cad_engine/cad_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const initialState = MeshEditState(
    active: true,
    busy: false,
    canUndo: false,
    canRedo: false,
    cursor: 0,
    revisionCount: 1,
    currentHandle: 42,
    sourcePath: '/model/source.step',
    sourceFormatId: 'step',
    workingCopyPath: '/cache/edit_0000.obj',
    meshWorkingCopy: true,
    sourceOverwritten: false,
  );

  testWidgets('mesh edit sheet fits a narrow phone and exposes safe controls',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showMeshEditSheet(
                  context: context,
                  initialState: initialState,
                  onApply: (_) async => initialState,
                  onUndo: () async => initialState,
                  onRedo: () async => initialState,
                  onReset: () async => initialState,
                  onDiscard: () async => initialState,
                ),
                child: const Text('打开编辑'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();

    expect(find.text('网格工作副本编辑'), findsOneWidget);
    expect(find.textContaining('STEP 源文件保持不变'), findsOneWidget);
    expect(find.text('应用变换'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('重做'), findsOneWidget);
    expect(find.text('重置'), findsOneWidget);
    expect(find.text('退出编辑并恢复原模型'), findsOneWidget);

    expect(find.byType(TextField), findsNWidgets(9));

    final undo = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('撤销'), matching: find.byType(OutlinedButton)),
    );
    final redo = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('重做'), matching: find.byType(OutlinedButton)),
    );
    final reset = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('重置'), matching: find.byType(OutlinedButton)),
    );
    expect(undo.onPressed, isNull);
    expect(redo.onPressed, isNull);
    expect(reset.onPressed, isNull);

    expect(tester.takeException(), isNull);
  });
}
