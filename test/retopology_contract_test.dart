import 'package:cad_engine/cad_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRetopoProvider implements RetopologyProvider {
  @override
  String get id => 'retopo.fake';

  @override
  RetopologyProviderProfile get profile => const RetopologyProviderProfile(
        supportsQuadDominant: true,
        supportsAllQuads: true,
        supportsBoundaryPreservation: true,
        supportsSharpPreservation: true,
        supportsSymmetry: true,
        supportsAttributeTransfer: true,
        supportsInteractiveGuides: false,
      );

  @override
  RetopologyAnalysis analyze(
    EngineeringDocument document,
    RetopologyRequest request,
  ) {
    final hasMesh = document.capabilities.contains(DocumentCapability.meshGeometry);
    return RetopologyAnalysis(
      available: hasMesh,
      providerId: id,
      warnings: request.useCase == RetopologyUseCase.animationAssist
          ? const ['Automatic retopology is not guaranteed deformation-ready.']
          : const [],
      reason: hasMesh ? '' : 'A mesh representation is required.',
    );
  }

  @override
  Future<RetopologyResult> retopologize(
    EngineeringDocument document,
    RetopologyRequest request,
  ) async {
    final output = EngineeringDocument(
      id: '${document.id}-quad',
      displayName: '${document.displayName} (quad)',
      provenance: DocumentProvenance(
        sourcePath: document.provenance.sourcePath,
        sourceFormatId: document.provenance.sourceFormatId,
        providerId: id,
      ),
      representations: const [EngineeringRepresentation.mesh],
      capabilities: CapabilitySet(const [
        DocumentCapability.meshGeometry,
        DocumentCapability.quadTopology,
      ]),
    );
    return RetopologyResult(
      document: output,
      providerId: id,
      report: const RetopologyQualityReport(
        inputFaceCount: 1000,
        outputFaceCount: 250,
        quadCount: 245,
        triangleCount: 5,
        ngonCount: 0,
        isManifold: true,
        boundaryPreserved: true,
      ),
    );
  }
}

EngineeringDocument _meshDocument() => EngineeringDocument(
      id: 'scan-1',
      displayName: 'scan.obj',
      provenance: const DocumentProvenance(
        sourcePath: '/tmp/scan.obj',
        sourceFormatId: 'obj',
        providerId: 'mesh.obj',
      ),
      representations: const [EngineeringRepresentation.mesh],
      capabilities: CapabilitySet(const [
        DocumentCapability.meshGeometry,
        DocumentCapability.normals,
        DocumentCapability.uvCoordinates,
      ]),
    );

void main() {
  test('retopology quality report exposes quad ratio', () {
    const report = RetopologyQualityReport(
      inputFaceCount: 100,
      outputFaceCount: 50,
      quadCount: 45,
      triangleCount: 5,
      ngonCount: 0,
    );
    expect(report.quadRatio, closeTo(0.9, 1e-9));
  });

  test('registry exposes provider analysis and output quad topology', () async {
    final registry = RetopologyRegistry()..register(_FakeRetopoProvider());
    final request = const RetopologyRequest(
      useCase: RetopologyUseCase.generalModeling,
      targetFaceCount: 250,
    );

    final analyses = registry.analyzeAll(_meshDocument(), request).toList();
    expect(analyses.single.available, isTrue);

    final result = await registry.byId('retopo.fake')!.retopologize(
          _meshDocument(),
          request,
        );
    expect(
      result.document.capabilities.contains(DocumentCapability.quadTopology),
      isTrue,
    );
    expect(result.report.quadRatio, closeTo(0.98, 1e-9));
  });
}
