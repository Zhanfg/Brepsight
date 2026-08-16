import 'package:cad_engine/cad_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engineering format catalog has unique ids and usable extensions', () {
    final ids = engineeringFormatCatalog.map((format) => format.id).toList();
    expect(ids.toSet().length, ids.length);

    for (final format in engineeringFormatCatalog) {
      expect(format.id.trim(), isNotEmpty);
      expect(format.label.trim(), isNotEmpty);
      expect(format.provider.trim(), isNotEmpty);
      expect(format.extensions, isNotEmpty);
      expect(format.extensions.every((ext) => ext.trim().isNotEmpty), isTrue);
    }
  });

  test('baseline mobile formats are represented in the catalog', () {
    const requiredIds = <String>{
      'step',
      'iges',
      'stl',
      '3mf',
      'obj',
      'gltf',
      'dxf',
      '3dm',
      'fcstd',
      'vtk',
      'gmsh',
      'gcode',
    };

    final ids = engineeringFormatCatalog.map((format) => format.id).toSet();
    expect(ids.containsAll(requiredIds), isTrue);
  });
}
