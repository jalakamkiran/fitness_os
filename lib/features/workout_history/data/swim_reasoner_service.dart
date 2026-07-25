import 'package:fitness_os/features/workout_history/data/qwen3_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/domain/offline_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

/// Prefers on-device Qwen3; falls back to offline rule reasoner.
class SwimReasonerService {
  SwimReasonerService({Qwen3SwimReasoner? qwen3})
      : _qwen3 = qwen3 ?? Qwen3SwimReasoner();

  final Qwen3SwimReasoner _qwen3;

  Qwen3SwimReasoner get qwen3 => _qwen3;

  Future<bool> get qwen3Ready => _qwen3.isInstalled();

  Future<SwimReasonerResult> reason({
    required SwimDiagnosisReport report,
    required List<SwimRecommendation> recommendations,
    required int workoutNumber,
    bool preferQwen3 = true,
  }) async {
    if (preferQwen3 && await _qwen3.isInstalled()) {
      final q = await _qwen3.reason(
        report: report,
        recommendations: recommendations,
        workoutNumber: workoutNumber,
      );
      if (q.ok) return q;
      // Fall through to offline if Qwen fails mid-run.
      final offline = reasonOffline(
        report: report,
        recommendations: recommendations,
      );
      return SwimReasonerResult(
        ok: offline.ok,
        source: 'offline',
        summary: offline.summary,
        orderedRecIds: offline.orderedRecIds,
        rationaleByRecId: offline.rationaleByRecId,
        notes: 'Qwen3 failed (${q.error}); used offline reasoner.\n'
            '${offline.notes ?? ''}',
        error: offline.ok ? null : offline.error,
      );
    }

    return reasonOffline(
      report: report,
      recommendations: recommendations,
    );
  }
}
