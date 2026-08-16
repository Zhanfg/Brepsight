import 'package:cad_engine/cad_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model task progress maps normalized fractions to integer percent', () {
    const progress = ModelTaskProgress(
      stage: ModelTaskStage.solving,
      fraction: 0.734,
      stageLabel: 'Quad solve',
    );
    expect(progress.percent, 73);
  });

  test('terminal task states are recognized', () {
    for (final state in [
      ModelTaskState.completed,
      ModelTaskState.failed,
      ModelTaskState.cancelled,
    ]) {
      final task = ModelTaskSnapshot(
        id: 'task-$state',
        kind: ModelTaskKind.retopology,
        title: 'Retopology',
        state: state,
        progress: const ModelTaskProgress(
          stage: ModelTaskStage.finalizing,
          fraction: 1,
        ),
        userInitiated: true,
      );
      expect(task.isTerminal, isTrue);
    }
  });

  test('material summary represents multiple UV sets and PBR texture semantics', () {
    final summary = MaterialAssetSummary(
      uvSets: const [
        UvSetDescriptor(index: 0, name: 'UVMap'),
        UvSetDescriptor(index: 1, name: 'Lightmap'),
      ],
      textures: const [
        TextureAssetDescriptor(
          id: 'albedo',
          storage: TextureStorage.externalFile,
          colorSpace: TextureColorSpace.srgb,
          uri: 'textures/albedo.png',
          mimeType: 'image/png',
        ),
        TextureAssetDescriptor(
          id: 'normal',
          storage: TextureStorage.externalFile,
          colorSpace: TextureColorSpace.data,
          uri: 'textures/normal.png',
          mimeType: 'image/png',
        ),
      ],
      materials: [
        MaterialDescriptor(
          id: 'mat-1',
          name: 'Body',
          model: MaterialModel.pbrMetallicRoughness,
          textures: const [
            TextureBinding(
              semantic: TextureSemantic.baseColor,
              textureId: 'albedo',
              uvSet: 0,
            ),
            TextureBinding(
              semantic: TextureSemantic.normal,
              textureId: 'normal',
              uvSet: 0,
            ),
          ],
        ),
      ],
    );

    expect(summary.hasUv, isTrue);
    expect(summary.uvSets.length, 2);
    expect(summary.textures[0].colorSpace, TextureColorSpace.srgb);
    expect(summary.textures[1].colorSpace, TextureColorSpace.data);
    expect(summary.materials.single.textures.length, 2);
  });
}
