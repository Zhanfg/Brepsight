import 'package:brepsight/src/viewer/viewer_workspace_page.dart';
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
        default:
          throw PlatformException(code: 'unexpected', message: call.method);
      }
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('STL opens as a model-first narrow-screen CAD workspace',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ViewerWorkspacePage(
          modelPath: '/tmp/MoeSizzlac - Noble 6 - Chest.stl',
          onExitViewer: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MoeSizzlac - Noble 6 - Chest.stl'), findsOneWidget);
    expect(find.text('STL · 49.2k 三角面 · N'), findsOneWidget);

    // Only active work modes live in the persistent bottom dock. Object
    // hierarchy belongs to the overflow/browser layer rather than occupying a
    // permanently disabled fourth slot.
    expect(find.text('测量'), findsOneWidget);
    expect(find.text('剖切'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('对象'), findsNothing);

    // Projection/display choices and standard orientations stay out of the
    // canvas until the dedicated CAD view sheet is opened.
    expect(find.text('透视'), findsNothing);
    expect(find.text('正交'), findsNothing);
    expect(find.text('文件'), findsNothing);
    expect(find.text('设置'), findsNothing);

    await tester.tap(find.byTooltip('视图与显示'));
    await tester.pumpAndSettle();

    expect(find.text('视图与显示'), findsOneWidget);
    expect(find.text('标准视角'), findsOneWidget);
    expect(find.text('等轴'), findsOneWidget);
    expect(find.text('前'), findsOneWidget);
    expect(find.text('后'), findsOneWidget);
    expect(find.text('左'), findsOneWidget);
    expect(find.text('右'), findsOneWidget);
    expect(find.text('顶'), findsOneWidget);
    expect(find.text('底'), findsOneWidget);
    expect(find.text('实体'), findsOneWidget);
    expect(find.text('边线'), findsOneWidget);
    expect(find.text('线框'), findsOneWidget);
    expect(find.text('浅色画布'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
