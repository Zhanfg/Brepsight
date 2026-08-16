import 'package:cad_engine/src/document/hierarchy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hierarchy maps provider-neutral parent child structure', () {
    final hierarchy = EngineeringHierarchy.fromList(<Object?>[
      <Object?, Object?>{
        'id': 'n0',
        'parentId': null,
        'kind': 'assembly',
        'name': 'Gearbox',
        'visible': true,
        'hasExactGeometry': true,
        'hasMesh': true,
        'sourceRef': '0:1:1',
        'transform': <Object?, Object?>{
          'matrix': EngineeringTransform.identity.matrix4x4,
        },
      },
      <Object?, Object?>{
        'id': 'n0/0',
        'parentId': 'n0',
        'kind': 'part',
        'name': 'Housing',
        'visible': true,
        'hasExactGeometry': true,
        'hasMesh': true,
        'sourceRef': '0:1:2',
      },
    ]);

    expect(hierarchy.roots().single.name, 'Gearbox');
    expect(hierarchy.childrenOf('n0').single.name, 'Housing');
    expect(hierarchy.childrenOf('n0').single.kind, EngineeringNodeKind.part);
    expect(hierarchy.childrenOf('n0').single.hasExactGeometry, isTrue);
  });

  test('invalid transform safely falls back to identity', () {
    final node = EngineeringHierarchyNode.fromMap(<Object?, Object?>{
      'id': 'x',
      'kind': 'mesh',
      'name': 'Imported mesh',
      'transform': <Object?, Object?>{'matrix': <Object?>[1, 2, 3]},
    });

    expect(node.transform.matrix4x4, EngineeringTransform.identity.matrix4x4);
    expect(node.visible, isTrue);
  });
}
