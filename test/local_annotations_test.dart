import 'dart:io';

import 'package:brepsight/src/viewer/local_annotations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local annotation JSON round-trips anchor and screenshot metadata', () {
    const annotation = LocalModelAnnotation(
      id: 'a-1',
      text: 'Check this mounting face.',
      createdAtMillis: 1_700_000_000_000,
      anchorKind: 'face',
      featureStableId: '42:17:faceCenter:0',
      triangleIndex: 17,
      featureIndex: 0,
      objectIndex: 2,
      x: 1.25,
      y: -2.5,
      z: 3.75,
      depth: 0.125,
      screenshotPngBase64: 'iVBORw0KGgo=',
    );

    final decoded = LocalModelAnnotation.decodeList(
      LocalModelAnnotation.encodeList(const [annotation]),
    );

    expect(decoded, hasLength(1));
    expect(decoded.single.id, 'a-1');
    expect(decoded.single.text, 'Check this mounting face.');
    expect(decoded.single.hasAnchor, isTrue);
    expect(decoded.single.hasScreenshot, isTrue);
    expect(decoded.single.featureStableId, '42:17:faceCenter:0');
    expect(decoded.single.objectIndex, 2);
    expect(decoded.single.x, 1.25);
  });

  test('damaged annotation row does not hide valid rows', () {
    final decoded = LocalModelAnnotation.decodeList(
      '[{"id":"bad"},{"id":"ok","text":"usable","createdAtMillis":2}]',
    );

    expect(decoded, hasLength(1));
    expect(decoded.single.id, 'ok');
  });

  test('model annotation identity is deterministic and samples file content', () async {
    final directory = await Directory.systemTemp.createTemp('brepsight_annotation_id_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/assembly.step');
    final bytes = List<int>.generate(220000, (index) => index % 251);
    await file.writeAsBytes(bytes, flush: true);

    Future<String> key() => ModelAnnotationIdentity.forModel(
          sourcePath: file.path,
          formatId: 'step',
          triangleCount: 1200,
          rootObjectCount: 4,
          hierarchyNodeCount: 9,
        );

    final first = await key();
    final second = await key();
    expect(first, second);
    expect(first, hasLength(16));

    bytes[110000] = (bytes[110000] + 37) % 255;
    await file.writeAsBytes(bytes, flush: true);
    final changed = await key();
    expect(changed, isNot(first));
  });
}
