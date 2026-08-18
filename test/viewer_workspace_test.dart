import 'package:brepsight/src/viewer/engineering_workspace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cad_engine/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'createViewport':
          return 7;
        case 'resizeViewport':
        case 'disposeViewport':
        case 'setProjection':
        case 'setDisplayMode':
        case 'fitAll':
        case 'orbit':
        case 'pan':
        case 'zoom':
          return null;
        case 'loadModel':
          return <Object?, Object?>{
            'ok': true,
            'displayName': 'MoeSizzlac - Noble 6 - Chest.stl',
            'message': 'OK',
            'formatId': 'stl',
            'triangleCount': 49186,
            'hasUv': false,
            'hasNormals': true,
            'exactGeometry': false,
            'rootObjectCount': 1,
            'hierarchyNodeCount': 1,
            'errorCode': 0,
          };
        case 'getObjectPresentation':
          return '[]';
        case 'getCurrentDocumentHandle':
          return 42;
        case 'getMeshEditState':
          return <Object?, Object?>{
            'active': false,
            'busy': false,
            'canUndo': false,
            'canRedo': false,
            'cursor': -1,
            'revisionCount': 0,
            'currentHandle': 0,
            'sourcePath': '',
            'sourceFormatId': 'stl',
            'workingCopyPath': '',
            'meshWorkingCopy': false,
            'sourceOverwritten': false,
          };
        case 'pickModelPoint':
          return <Object?>[1.25, -2.5, 3.75, 17, 0.125];
        default:
          throw PlatformException(code: 'unexpected', message: call.method);
      }
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpWorkspace(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: brightness),
        home: EngineeringWorkspacePage(
          modelPath: '/tmp/MoeSizzlac - Noble 6 - Chest.stl',
          onExitViewer: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('STL opens as a model-first narrow-screen engineering workspace',
      (tester) async {
    await pumpWorkspace(tester, Brightness.light);

    expect(find.text('MoeSizzlac - Noble 6 - Chest.stl'), findsOneWidget);
    expect(find.text('STL · 49.2k 三角面 · N'), findsOneWidget);
    expect(find.text('测量'), findsOneWidget);
    expect(find.text('剖切'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('文件'), findsNothing);
    expect(find.text('设置'), findsNothing);

    await tester.tap(find.byTooltip('视图与显示'));
    await tester.pumpAndSettle();
    expect(find.text('标准视角'), findsOneWidget);
    expect(find.text('等轴'), findsOneWidget);
    expect(find.text('实体'), findsOneWidget);
    expect(find.text('边线'), findsOneWidget);
    expect(find.text('线框'), findsOneWidget);
    expect(find.textContaining('亮色模式使用浅灰蓝画布'), findsOneWidget);
    expect(find.text('浅色画布'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark workspace exposes restrained night palette guidance',
      (tester) async {
    await pumpWorkspace(tester, Brightness.dark);
    await tester.tap(find.byTooltip('视图与显示'));
    await tester.pumpAndSettle();
    expect(find.textContaining('暗色模式使用深石墨画布'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('engineering operations expose conversion and connected split',
      (tester) async {
    await pumpWorkspace(tester, Brightness.light);
    await tester.tap(find.byTooltip('工程操作'));
    await tester.pumpAndSettle();
    expect(find.text('转换 / 导出'), findsOneWidget);
    expect(find.text('拆分连通部件'), findsOneWidget);
    expect(find.textContaining('OBJ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('measurement sheet exposes coordinate area and precision crosshair',
      (tester) async {
    await pumpWorkspace(tester, Brightness.light);

    await tester.tap(find.text('测量'));
    await tester.pumpAndSettle();
    expect(find.text('点坐标'), findsOneWidget);
    expect(find.text('三点面积'), findsOneWidget);
    expect(find.text('精确十字光标'), findsOneWidget);

    await tester.tap(find.text('点坐标'));
    await tester.pumpAndSettle();
    expect(find.textContaining('坐标 · 0 点'), findsOneWidget);

    await tester.tap(find.text('测量'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精确十字光标'));
    await tester.pump();
    await tester.tap(find.text('点坐标'));
    await tester.pumpAndSettle();

    expect(find.text('捕捉中心'), findsOneWidget);
    await tester.tap(find.text('捕捉中心'));
    await tester.pumpAndSettle();

    expect(find.textContaining('拾取 · 三角面 #17'), findsOneWidget);
    expect(find.textContaining('X 1.25 · Y -2.5 · Z 3.75'), findsWidgets);
    expect(find.textContaining('ID 42:17'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
