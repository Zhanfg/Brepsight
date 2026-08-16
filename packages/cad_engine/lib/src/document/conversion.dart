import 'engineering_document.dart';
import 'writer.dart';

enum ConversionPlanStatus {
  lossless,
  lossy,
  unavailable,
}

class ConversionPlan {
  const ConversionPlan({
    required this.status,
    required this.outputFormatId,
    required this.analysis,
    this.writerId,
  });

  final ConversionPlanStatus status;
  final String outputFormatId;
  final String? writerId;
  final ExportAnalysis analysis;

  bool get canConvert => status != ConversionPlanStatus.unavailable;

  /// Simple UI ranking score. 1.0 means no currently-known capability loss.
  double get retentionScore {
    if (!canConvert) return 0;
    final relevant = analysis.impacts.where(
      (impact) => impact.disposition != CapabilityDisposition.notApplicable,
    );
    final total = relevant.length;
    if (total == 0) return 1;

    var points = 0.0;
    for (final impact in relevant) {
      switch (impact.disposition) {
        case CapabilityDisposition.preserved:
          points += 1;
        case CapabilityDisposition.degraded:
          points += 0.5;
        case CapabilityDisposition.lost:
        case CapabilityDisposition.notApplicable:
          break;
      }
    }
    return points / total;
  }
}

class ConversionPlanner {
  const ConversionPlanner(this.writers);

  final WriterRegistry writers;

  ConversionPlan plan(EngineeringDocument document, String outputFormatId) {
    final candidates = writers.forFormat(outputFormatId).toList();
    if (candidates.isEmpty) {
      return ConversionPlan(
        status: ConversionPlanStatus.unavailable,
        outputFormatId: outputFormatId,
        analysis: ExportAnalysis(
          canExport: false,
          outputFormatId: outputFormatId,
          impacts: const [],
          reason: 'No writer is registered for $outputFormatId.',
        ),
      );
    }

    EngineeringWriter? bestWriter;
    ExportAnalysis? bestAnalysis;
    double bestScore = -1;

    for (final writer in candidates) {
      final analysis = writer.analyze(document);
      if (!analysis.canExport) continue;
      final score = _score(analysis);
      if (score > bestScore) {
        bestScore = score;
        bestWriter = writer;
        bestAnalysis = analysis;
      }
    }

    if (bestWriter == null || bestAnalysis == null) {
      return ConversionPlan(
        status: ConversionPlanStatus.unavailable,
        outputFormatId: outputFormatId,
        analysis: candidates.first.analyze(document),
      );
    }

    final isLossy = bestAnalysis.impacts.any(
      (impact) =>
          impact.disposition == CapabilityDisposition.degraded ||
          impact.disposition == CapabilityDisposition.lost,
    );

    return ConversionPlan(
      status: isLossy ? ConversionPlanStatus.lossy : ConversionPlanStatus.lossless,
      outputFormatId: outputFormatId,
      writerId: bestWriter.id,
      analysis: bestAnalysis,
    );
  }

  double _score(ExportAnalysis analysis) {
    var score = 0.0;
    for (final impact in analysis.impacts) {
      switch (impact.disposition) {
        case CapabilityDisposition.preserved:
          score += 2;
        case CapabilityDisposition.degraded:
          score += 1;
        case CapabilityDisposition.lost:
          score -= 2;
        case CapabilityDisposition.notApplicable:
          break;
      }
    }
    return score;
  }
}
