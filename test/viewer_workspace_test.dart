import 'package:brepsight/src/viewer/engineering_workspace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cad_engine/methods');
  final displayCommands = <String>[];

  setUp(() {
    displayCommands.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'createViewport':
              return 7;
            case 'resizeViewport':
            case 'disposeViewport':
            case 'setProjection':
            case 'fitAll':
            case 'orbit':
            case 'pan':
            case 'zoom':
              return null;
            case 'setDisplayMode':
              final arguments = call.arguments as Map<Object?, Object?>?;
              final mode = arguments?['mode'] as String?;
              if (mode != null) displayCommands.add(mode);
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
              return '[{"id":"body-0","label":"Chest","type":"mesh","parentId":"","visible":true,"effectiveVisible":true,"hasGeometry":true,"hasBaseColor":true,"baseColor":[0.7,0.76,0.84]},{"id":"body-1","label":"Plate","type":"mesh","parentId":"","visible":true,"effectiveVisible":true,"hasGeometry":true,"hasBaseColor":false,"baseColor":[0.7,0.76,0.84]}]';
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
              return <Object?>[1.25, -2.5, 3.75, 17, 0.125, 1, 0, 0];
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

  testWidgets(
    'STL opens as a model-first narrow-screen engineering workspace',
    (tester) async {
      await pumpWorkspace(tester, Brightness.light);

      expect(find.text('MoeSizzlac - Noble 6 - Chest.stl'), findsOneWidget);
      expect(find.text('STL · 49.2k 三角面 · N'), findsOneWidget);
      expect(find.text('选择'), findsOneWidget);
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
    },
  );

  testWidgets('dark workspace exposes restrained night palette guidance', (
    tester,
  ) async {
    await pumpWorkspace(tester, Brightness.dark);
    await tester.tap(find.byTooltip('视图与显示'));
    await tester.pumpAndSettle();
    expect(find.textContaining('暗色模式使用深石墨画布'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('engineering operations expose conversion and connected split', (
    tester,
  ) async {
    await pumpWorkspace(tester, Brightness.light);
    await tester.tap(find.byTooltip('工程操作'));
    await tester.pumpAndSettle();
    expect(find.text('转换 / 导出'), findsOneWidget);
    expect(find.text('拆分连通部件'), findsOneWidget);
    expect(find.text('爆炸视图'), findsOneWidget);
    expect(find.textContaining('OBJ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'exploded assembly view drives native per-object display offsets',
    (tester) async {
      await pumpWorkspace(tester, Brightness.light);
      await tester.tap(find.byTooltip('工程操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('爆炸视图'));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(0.6);
      await tester.pumpAndSettle();

      expect(displayCommands.any((mode) => mode == 'explode:0.6000'), isTrue);
      expect(find.text('60%'), findsOneWidget);
      await tester.tap(find.text('复位'));
      await tester.pumpAndSettle();
      expect(displayCommands.any((mode) => mode == 'explode:0.0000'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection filters persist highlight identity and expose properties',
    (tester) async {
      await pumpWorkspace(tester, Brightness.light);

      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(find.text('选择过滤'), findsOneWidget);
      expect(find.text('顶点'), findsOneWidget);
      expect(find.text('边'), findsOneWidget);
      expect(find.text('面'), findsOneWidget);
      expect(find.text('对象'), findsWidgets);

      await tester.tap(find.text('顶点'));
      await tester.pumpAndSettle();
      expect(find.text('顶点选择'), findsOneWidget);

      await tester.tapAt(const Offset(180, 360));
      await tester.pumpAndSettle();
      expect(find.textContaining('顶点 · #17'), findsOneWidget);

      await tester.tap(find.textContaining('顶点 · #17'));
      await tester.pumpAndSettle();
      expect(find.text('选择属性'), findsOneWidget);
      expect(find.text('42:17:vertex:0'), findsOneWidget);
      expect(find.text('Chest'), findsOneWidget);
      expect(find.text('body-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'measurement sheet exposes coordinate area and precision crosshair',
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
      expect(find.text('坐标测量 · 选择 1 个点'), findsOneWidget);
      final statusRect = tester.getRect(find.text('坐标测量 · 选择 1 个点'));
      final captureRect = tester.getRect(find.text('捕捉中心'));
      expect(statusRect.bottom, lessThan(captureRect.top));

      await tester.tap(find.text('捕捉中心'));
      await tester.pumpAndSettle();

      expect(find.textContaining('拾取 · 三角面 #17'), findsOneWidget);
      expect(find.textContaining('X 1.25 · Y -2.5 · Z 3.75'), findsWidgets);
      expect(find.textContaining('ID 42:17'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
