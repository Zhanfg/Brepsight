import 'dart:math' as math;

import 'package:cad_engine/v01_tools.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

CadPickPoint point(
  double x,
  double y,
  double z, {
  int triangle = 0,
  int document = 7,
}) =>
    CadPickPoint(
      x: x,
      y: y,
      z: z,
      triangleIndex: triangle,
      depth: 0.5,
      documentHandle: document,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cad_engine/methods');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('stable pick identity is document-scoped and triangle-stable', () {
    expect(point(1, 2, 3, triangle: 42, document: 9).stableId, '9:42');
    expect(point(1, 2, 3, triangle: 42, document: 10).stableId, '10:42');
  });

  test('distance, angle, radius and 3D area produce known engineering values', () {
    final a = point(0, 0, 0);
    final b = point(3, 4, 0);
    expect(CadMeasurement.distance(a, b), closeTo(5.0, 1e-12));

    final angle = CadMeasurement.angle(
      point(1, 0, 0),
      point(0, 0, 0),
      point(0, 1, 0),
    );
    expect(angle, closeTo(90.0, 1e-10));

    final radius = CadMeasurement.radius(
      point(1, 0, 0),
      point(0, 1, 0),
      point(-1, 0, 0),
    );
    expect(radius, closeTo(1.0, 1e-10));

    expect(
      CadMeasurement.area(
        point(0, 0, 0),
        point(3, 0, 0),
        point(0, 4, 0),
      ),
      closeTo(6.0, 1e-12),
    );
    expect(
      CadMeasurement.area(
        point(0, 0, 0),
        point(0, 3, 0),
        point(0, 0, 4),
      ),
      closeTo(6.0, 1e-12),
    );
  });

  test('degenerate angle and radius are rejected and area collapses to zero', () {
    expect(
      CadMeasurement.angle(point(0, 0, 0), point(0, 0, 0), point(1, 0, 0)),
      isNull,
    );
    expect(
      CadMeasurement.radius(point(0, 0, 0), point(1, 0, 0), point(2, 0, 0)),
      isNull,
    );
    expect(
      CadMeasurement.area(point(0, 0, 0), point(1, 0, 0), point(2, 0, 0)),
      closeTo(0.0, 1e-12),
    );
  });

  test('measurement mode exposes coordinate and area workflows', () {
    expect(CadMeasurementMode.values, contains(CadMeasurementMode.coordinate));
    expect(CadMeasurementMode.values, contains(CadMeasurementMode.area));
  });

  test('import progress and cancellation preserve the method-channel contract', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getImportProgress') {
        return <Object?, Object?>{
          'active': true,
          'taskId': 12,
          'path': '/tmp/assembly.step',
          'stage': 'importing',
          'progress': 41,
          'cancelRequested': false,
        };
      }
      if (call.method == 'cancelImport') return true;
      throw PlatformException(code: 'unexpected', message: call.method);
    });

    final progress = await CadEngineV01Tools.instance.importProgress();
    expect(progress.active, isTrue);
    expect(progress.taskId, 12);
    expect(progress.path, '/tmp/assembly.step');
    expect(progress.stage, 'importing');
    expect(progress.progress, 41);
    expect(progress.cancelRequested, isFalse);
    expect(await CadEngineV01Tools.instance.cancelImport(), isTrue);
    expect(calls.map((call) => call.method), ['getImportProgress', 'cancelImport']);
  });

  test('pick and section-plane commands forward exact viewport geometry', () async {
    MethodCall? pickCall;
    MethodCall? sectionCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickModelPoint') {
        pickCall = call;
        return <Object?>[1.25, -2.5, 3.75, 17, 0.125];
      }
      if (call.method == 'setSectionPlane') {
        sectionCall = call;
        return true;
      }
      throw PlatformException(code: 'unexpected', message: call.method);
    });

    final picked = await CadEngineV01Tools.instance.pickModelPoint(
      documentHandle: 33,
      width: 1080,
      height: 1920,
      orbitX: 0.5,
      orbitY: -0.2,
      panX: 3,
      panY: -4,
      zoom: 1.5,
      orthographic: true,
      screenX: 320,
      screenY: 640,
    );
    expect(picked, isNotNull);
    expect(picked!.stableId, '33:17');
    expect(picked.x, closeTo(1.25, 1e-12));
    expect(picked.depth, closeTo(0.125, 1e-12));
    final pickArgs = Map<Object?, Object?>.from(pickCall!.arguments as Map);
    expect(pickArgs['handle'], 33);
    expect(pickArgs['orthographic'], isTrue);
    expect(pickArgs['screenX'], 320.0);
    expect(pickArgs['screenY'], 640.0);

    expect(
      await CadEngineV01Tools.instance.setSectionPlane(
        enabled: true,
        nx: 0,
        ny: 1,
        nz: 0,
        offset: 12.5,
      ),
      isTrue,
    );
    final sectionArgs = Map<Object?, Object?>.from(sectionCall!.arguments as Map);
    expect(sectionArgs['enabled'], isTrue);
    expect(sectionArgs['ny'], 1.0);
    expect(sectionArgs['offset'], closeTo(12.5, math.pow(10, -12).toDouble()));
  });
}
