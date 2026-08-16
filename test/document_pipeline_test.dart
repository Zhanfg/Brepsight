import 'package:cad_engine/cad_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeImporter implements EngineeringImporter {
  _FakeImporter({required this.id, required this.score, required this.formatId});

  @override
  final String id;
  final int score;
  final String formatId;

  @override
  Set<String> get supportedFormatIds => {formatId};

  @override
  Future<ImportProbe> probe(ImportRequest request) async =>
      ImportProbe(score: score, formatId: formatId);

  @override
  Future<EngineeringDocument> importDocument(ImportRequest request) async {
    return EngineeringDocument(
      id: 'doc-$id',
      displayName: request.path.split('/').last,
      provenance: DocumentProvenance(
        sourcePath: request.path,
        sourceFormatId: formatId,
        providerId: id,
      ),
      representations: const {EngineeringRepresentation.exactGeometry},
      capabilities: CapabilitySet(const {
        DocumentCapability.exactGeometry,
        DocumentCapability.hierarchy,
        DocumentCapability.units,
      }),
      unit: 'mm',
      nativeHandle: 42,
    );
  }
}

class _FakeWriter implements EngineeringWriter {
  _FakeWriter({
    required this.id,
    required this.outputFormatId,
    required this.analysis,
  });

  @override
  final String id;
  @override
  final String outputFormatId;
  final ExportAnalysis analysis;

  @override
  ExportAnalysis analyze(EngineeringDocument document) => analysis;

  @override
  Future<ExportResult> exportDocument(
    EngineeringDocument document, {
    required String outputPath,
  }) async {
    return ExportResult(
      ok: true,
      outputPath: outputPath,
      outputFormatId: outputFormatId,
    );
  }
}

void main() {
  test('importer registry selects the strongest probe', () async {
    final pipeline = EngineeringDocumentPipeline();
    pipeline.importers.register(
      _FakeImporter(id: 'weak', score: 40, formatId: 'step'),
    );
    pipeline.importers.register(
      _FakeImporter(id: 'occt.step', score: 100, formatId: 'step'),
    );

    final document = await pipeline.open(
      const ImportRequest(path: '/tmp/gearbox.step', extension: 'step'),
    );

    expect(document.provenance.providerId, 'occt.step');
    expect(document.nativeHandle, 42);
    expect(
      document.capabilities.contains(DocumentCapability.exactGeometry),
      isTrue,
    );
  });

  test('conversion planner prefers the writer with less semantic loss', () {
    final document = EngineeringDocument(
      id: 'assembly',
      displayName: 'assembly.step',
      provenance: const DocumentProvenance(
        sourcePath: '/tmp/assembly.step',
        sourceFormatId: 'step',
        providerId: 'occt.step',
      ),
      representations: const {EngineeringRepresentation.exactGeometry},
      capabilities: CapabilitySet(const {
        DocumentCapability.exactGeometry,
        DocumentCapability.hierarchy,
        DocumentCapability.materials,
        DocumentCapability.units,
      }),
    );

    final registry = WriterRegistry();
    registry.register(
      _FakeWriter(
        id: '3mf.basic',
        outputFormatId: '3mf',
        analysis: const ExportAnalysis(
          canExport: true,
          outputFormatId: '3mf',
          impacts: [
            CapabilityImpact(
              capability: DocumentCapability.exactGeometry,
              disposition: CapabilityDisposition.lost,
            ),
            CapabilityImpact(
              capability: DocumentCapability.hierarchy,
              disposition: CapabilityDisposition.degraded,
            ),
            CapabilityImpact(
              capability: DocumentCapability.materials,
              disposition: CapabilityDisposition.lost,
            ),
            CapabilityImpact(
              capability: DocumentCapability.units,
              disposition: CapabilityDisposition.preserved,
            ),
          ],
        ),
      ),
    );
    registry.register(
      _FakeWriter(
        id: '3mf.rich',
        outputFormatId: '3mf',
        analysis: const ExportAnalysis(
          canExport: true,
          outputFormatId: '3mf',
          impacts: [
            CapabilityImpact(
              capability: DocumentCapability.exactGeometry,
              disposition: CapabilityDisposition.lost,
            ),
            CapabilityImpact(
              capability: DocumentCapability.hierarchy,
              disposition: CapabilityDisposition.preserved,
            ),
            CapabilityImpact(
              capability: DocumentCapability.materials,
              disposition: CapabilityDisposition.preserved,
            ),
            CapabilityImpact(
              capability: DocumentCapability.units,
              disposition: CapabilityDisposition.preserved,
            ),
          ],
        ),
      ),
    );

    final plan = ConversionPlanner(registry).plan(document, '3mf');

    expect(plan.canConvert, isTrue);
    expect(plan.status, ConversionPlanStatus.lossy);
    expect(plan.writerId, '3mf.rich');
    expect(plan.analysis.lostCount, 1);
    expect(plan.retentionScore, 0.75);
  });

  test('missing writer returns an unavailable plan', () {
    final document = EngineeringDocument(
      id: 'mesh',
      displayName: 'scan.ply',
      provenance: const DocumentProvenance(
        sourcePath: '/tmp/scan.ply',
        sourceFormatId: 'ply',
        providerId: 'mesh.ply',
      ),
      representations: const {EngineeringRepresentation.pointCloud},
      capabilities: CapabilitySet(const {DocumentCapability.pointAttributes}),
    );

    final plan = ConversionPlanner(WriterRegistry()).plan(document, 'step');
    expect(plan.status, ConversionPlanStatus.unavailable);
    expect(plan.canConvert, isFalse);
  });
}
