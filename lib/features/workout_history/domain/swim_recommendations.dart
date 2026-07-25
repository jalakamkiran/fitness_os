import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

/// Allow-listed swim recommendation (deterministic). Never LLM-authored.
class SwimRecommendation {
  const SwimRecommendation({
    required this.id,
    required this.title,
    required this.detail,
    required this.sourceDiagnosisIds,
    required this.metricIds,
    this.bibleHint,
  });

  final String id;
  final String title;
  final String detail;
  final List<String> sourceDiagnosisIds;
  final List<String> metricIds;
  final String? bibleHint;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'detail': detail,
        'sourceDiagnosisIds': sourceDiagnosisIds,
        'metricIds': metricIds,
        if (bibleHint != null) 'bibleHint': bibleHint,
      };
}

/// Catalog keyed by recommendation id — only these may appear in coach output.
const Map<String, SwimRecommendation> kSwimRecCatalog = {
  'shorter_sets': SwimRecommendation(
    id: 'shorter_sets',
    title: 'Shorter sets with full recovery',
    detail:
        'Split the session into shorter repeats (e.g. 4×25–50) with enough rest '
        'so form holds — reduces late-set fatigue onset.',
    sourceDiagnosisIds: ['fatigue_onset'],
    metricIds: ['paceDecayPct'],
    bibleHint: 'Ch.24 fatigue / set design',
  ),
  'technique_before_volume': SwimRecommendation(
    id: 'technique_before_volume',
    title: 'Technique before volume',
    detail:
        'Prioritize easy technique lengths before adding distance. Stop a set '
        'when stroke quality drops instead of grinding.',
    sourceDiagnosisIds: ['fatigue_onset', 'efficiency_decline'],
    metricIds: ['paceDecayPct', 'swolfDelta'],
    bibleHint: 'Ch.25 efficiency',
  ),
  'even_split_focus': SwimRecommendation(
    id: 'even_split_focus',
    title: 'Even-split pacing focus',
    detail:
        'Aim for similar interval times end-to-end. Use a pace goal per length '
        'and avoid surging early.',
    sourceDiagnosisIds: ['pacing_uneven'],
    metricIds: ['paceCvPct'],
    bibleHint: 'Ch.23 pacing',
  ),
  'stroke_count_drill': SwimRecommendation(
    id: 'stroke_count_drill',
    title: 'Stroke-count awareness drill',
    detail:
        'Count strokes per length for 4–6 lengths at easy effort. Hold or lower '
        'count before adding speed.',
    sourceDiagnosisIds: ['efficiency_decline'],
    metricIds: ['swolfDelta', 'avgSwolf'],
    bibleHint: 'Ch.25 stroke efficiency',
  ),
  'keep_steady_load': SwimRecommendation(
    id: 'keep_steady_load',
    title: 'Keep the steady template',
    detail:
        'Pacing looked controlled — repeat a similar structure next session and '
        'nudge volume only slightly.',
    sourceDiagnosisIds: ['pacing_steady', 'no_strong_signal', 'trends_stable'],
    metricIds: ['paceCvPct', 'paceDecayPct'],
    bibleHint: 'Ch.23 consistency',
  ),
  'log_another_session': SwimRecommendation(
    id: 'log_another_session',
    title: 'Log another controlled swim',
    detail:
        'Trends need ≥2 sessions. Next swim: continuous freestyle, counted '
        'lengths, minimal floating — calibrates length vs interval.',
    sourceDiagnosisIds: ['trends_need_sessions', 'length_semantics_open'],
    metricIds: ['sessionCount', 'lengthCoveragePartial'],
    bibleHint: 'Probe / glossary',
  ),
  'ease_volume_spike': SwimRecommendation(
    id: 'ease_volume_spike',
    title: 'Ease into volume changes',
    detail:
        'Latest distance jumped vs prior — step volume by ~10–20% rather than '
        'large spikes when fatigue signals appear.',
    sourceDiagnosisIds: ['trend_volume_up'],
    metricIds: ['volumeVsPriorPct', 'distanceM'],
    bibleHint: 'Ch.24 load',
  ),
  'rebuild_efficiency': SwimRecommendation(
    id: 'rebuild_efficiency',
    title: 'Rebuild efficiency before speed',
    detail:
        'SWOLF trending worse across sessions — emphasize easy technique and '
        'stroke count before chasing pace PRs.',
    sourceDiagnosisIds: ['trend_swolf_worse'],
    metricIds: ['avgSwolf', 'swolfDelta'],
    bibleHint: 'Ch.25',
  ),
};

/// Map diagnoses → allow-listed recs (deduped, stable order).
List<SwimRecommendation> recommendationsForDiagnoses(
  List<SwimDiagnosis> diagnoses,
) {
  final ids = <String>{};
  final out = <SwimRecommendation>[];
  for (final d in diagnoses) {
    for (final rec in kSwimRecCatalog.values) {
      if (!rec.sourceDiagnosisIds.contains(d.id)) continue;
      if (ids.add(rec.id)) out.add(rec);
    }
  }
  return out;
}

List<SwimRecommendation> recommendationsForReport(SwimDiagnosisReport report) {
  return recommendationsForDiagnoses([
    ...report.sessionDiagnoses,
    ...report.trendDiagnoses,
  ]);
}

/// Coach payload — only these fields go to Gemini.
Map<String, dynamic> buildCoachPromptPayload({
  required SwimDiagnosisReport report,
  required List<SwimRecommendation> recommendations,
  required int workoutNumber,
}) {
  return {
    'workoutNumber': workoutNumber,
    'instructions':
        'You are a swim coach narrator. Explain and prioritize ONLY the given '
        'recommendations. Never invent metrics, diagnoses, or drills. '
        'Return JSON: {"summary": string, "orderedRecIds": string[], "notes": string}. '
        'orderedRecIds must be a subset of recommendation ids provided.',
    'diagnoses': [
      for (final d in [...report.sessionDiagnoses, ...report.trendDiagnoses])
        {
          'id': d.id,
          'title': d.title,
          'summary': d.summary,
          'confidence': d.confidence.name,
          'metricIds': d.metricIds,
        },
    ],
    'recommendations': [for (final r in recommendations) r.toJson()],
    'allowedRecIds': [for (final r in recommendations) r.id],
  };
}

/// Keep only rec IDs that exist in [allowed].
List<String> filterCoachOrderedIds(
  List<dynamic>? raw,
  Set<String> allowed,
) {
  if (raw == null) return const [];
  final out = <String>[];
  for (final item in raw) {
    if (item is! String) continue;
    if (allowed.contains(item) && !out.contains(item)) out.add(item);
  }
  return out;
}

SwimConfidence confidenceForRecs(List<SwimDiagnosis> diagnoses) {
  if (diagnoses.isEmpty) return SwimConfidence.low;
  if (diagnoses.any((d) => d.confidence == SwimConfidence.low)) {
    return SwimConfidence.med;
  }
  if (diagnoses.every((d) => d.confidence == SwimConfidence.high)) {
    return SwimConfidence.high;
  }
  return SwimConfidence.med;
}
