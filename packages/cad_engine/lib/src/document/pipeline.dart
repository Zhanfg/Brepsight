import 'conversion.dart';
import 'engineering_document.dart';
import 'importer.dart';
import 'writer.dart';

class NoImporterFound implements Exception {
  const NoImporterFound(this.path);

  final String path;

  @override
  String toString() => 'No importer could handle $path.';
}

class ConversionUnavailable implements Exception {
  const ConversionUnavailable(this.outputFormatId, this.reason);

  final String outputFormatId;
  final String reason;

  @override
  String toString() => 'Cannot convert to $outputFormatId: $reason';
}

class EngineeringDocumentPipeline {
  EngineeringDocumentPipeline({
    ImporterRegistry? importers,
    WriterRegistry? writers,
  })  : importers = importers ?? ImporterRegistry(),
        writers = writers ?? WriterRegistry();

  final ImporterRegistry importers;
  final WriterRegistry writers;

  Future<EngineeringDocument> open(ImportRequest request) async {
    final resolution = await importers.resolve(request);
    if (resolution == null) throw NoImporterFound(request.path);
    return resolution.importer.importDocument(request);
  }

  ConversionPlan planConversion(
    EngineeringDocument document,
    String outputFormatId,
  ) =>
      ConversionPlanner(writers).plan(document, outputFormatId);

  Future<ExportResult> convert(
    EngineeringDocument document,
    String outputFormatId, {
    required String outputPath,
  }) async {
    final plan = planConversion(document, outputFormatId);
    if (!plan.canConvert || plan.writerId == null) {
      throw ConversionUnavailable(outputFormatId, plan.analysis.reason);
    }

    final writer = writers.byId(plan.writerId!);
    if (writer == null) {
      throw StateError('Planned writer disappeared: ${plan.writerId}');
    }

    return writer.exportDocument(document, outputPath: outputPath);
  }
}
