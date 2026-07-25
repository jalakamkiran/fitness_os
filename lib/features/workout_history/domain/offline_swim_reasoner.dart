import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

/// Result of swim reasoning (on-device Qwen3 or offline ranker).
class SwimReasonerResult {
  const SwimReasonerResult({
    required this.ok,
    required this.source,
    this.summary,
    this.orderedRecIds = const [],
    this.rationaleByRecId = const {},
    this.notes,
    this.error,
  });

  final bool ok;
  /// `qwen3` | `offline`
  final String source;
  final String? summary;
  final List<String> orderedRecIds;
  final Map<String, String> rationaleByRecId;
  final String? notes;
  final String? error;
}

/// Deterministic reasoning ranker — works with no model download.
///
/// Scores allow-listed recs from diagnosis severity/confidence so the product
/// still "improves" decisions offline.
SwimReasonerResult reasonOffline({
  required SwimDiagnosisReport report,
  required List<SwimRecommendation> recommendations,
}) {
  if (recommendations.isEmpty) {
    return const SwimReasonerResult(
      ok: false,
      source: 'offline',
      error: 'No allow-listed recommendations for this session.',
    );
  }

  final diagnoses = [...report.sessionDiagnoses, ...report.trendDiagnoses];
  final score = <String, int>{};
  final why = <String, String>{};

  for (final rec in recommendations) {
    var s = 0;
    final reasons = <String>[];
    for (final d in diagnoses) {
      if (!rec.sourceDiagnosisIds.contains(d.id)) continue;
      final conf = switch (d.confidence) {
        SwimConfidence.high => 30,
        SwimConfidence.med => 20,
        SwimConfidence.low => 10,
      };
      final severity = _diagnosisSeverity(d.id);
      s += conf + severity;
      reasons.add('${d.id} (${d.confidence.name})');
    }
    // Prefer actionable training fixes over meta/probe notes.
    if (rec.id == 'log_another_session') s -= 15;
    score[rec.id] = s;
    why[rec.id] = reasons.isEmpty
        ? 'Mapped from session evidence'
        : 'Driven by ${reasons.join(', ')}';
  }

  final ordered = [...recommendations]
    ..sort((a, b) => (score[b.id] ?? 0).compareTo(score[a.id] ?? 0));
  final top = ordered.take(3).toList();
  final summary = top.isEmpty
      ? 'No priority actions.'
      : 'Priority: ${top.map((r) => r.title).join(' → ')}. '
          'Focus on the top item before adding volume.';

  return SwimReasonerResult(
    ok: true,
    source: 'offline',
    summary: summary,
    orderedRecIds: ordered.map((r) => r.id).toList(),
    rationaleByRecId: {
      for (final r in ordered) r.id: why[r.id] ?? '',
    },
    notes: 'Offline reasoner (rules). Install Qwen3 0.6B for on-device LLM ranking.',
  );
}

int _diagnosisSeverity(String id) {
  switch (id) {
    case 'fatigue_onset':
    case 'efficiency_decline':
    case 'pacing_uneven':
      return 40;
    case 'trend_pace_slower':
    case 'trend_swolf_worse':
    case 'trend_volume_up':
      return 25;
    case 'length_semantics_open':
    case 'trends_need_sessions':
      return 5;
    case 'pacing_steady':
    case 'efficiency_improve':
    case 'trends_stable':
    case 'no_strong_signal':
      return 15;
    default:
      return 10;
  }
}
