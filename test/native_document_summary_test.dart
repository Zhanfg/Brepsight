import 'package:cad_engine/cad_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load result preserves exact CAD metadata', () {
    final result = CadLoadResult.fromMap(<Object?, Object?>{
      'ok': true,
      'displayName': 'assembly.step',
      'message': 'OK',
      'formatId': 'step',
      'triangleCount': 1240,
      'hasUv': false,
      'hasNormals': true,
      'exactGeometry': true,
      'rootObjectCount': 2,
      'hierarchyNodeCount': 17,
      'errorCode': 0,
    });

    expect(result.ok, isTrue);
    expect(result.formatId, 'step');
    expect(result.exactGeometry, isTrue);
    expect(result.rootObjectCount, 2);
    expect(result.hierarchyNodeCount, 17);
    expect(result.triangleCount, 1240);
  });

  test('native summary keeps mesh-only documents explicitly non-exact', () {
    final summary = NativeDocumentSummary.fromMap(<Object?, Object?>{
      'handle': 9,
      'sourcePath': '/cache/part.obj',
      'formatId': 'obj',
      'triangleCount': 12,
      'hasUv': true,
      'hasNormals': true,
      'exactGeometry': false,
      'rootObjectCount': 0,
      'hierarchyNodeCount': 0,
      'committed': true,
      'current': true,
    });

    expect(summary.exactGeometry, isFalse);
    expect(summary.hasUv, isTrue);
    expect(summary.rootObjectCount, 0);
    expect(summary.hierarchyNodeCount, 0);
  });
}
