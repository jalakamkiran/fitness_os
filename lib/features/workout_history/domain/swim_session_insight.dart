import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

/// Athlete-safe session insight for the coach fold (F1).
///
/// Pure domain — no prefs, orientation, or Flutter types. Presentation owns
/// invent-guard filtering, HR lock peel, and rendering.
class SwimSessionInsight {
  const SwimSessionInsight({
    required this.story,
    required this.chips,
    required this.kpis,
    required this.secondaryFindings,
    this.storyDiagnosisId,
    this.primaryTip,
  });

  /// Plain-language session story (always present; may be coverage-honest).
  final String story;

  /// Winning session diagnosis id that drove [story] / [primaryTip], if any.
  final String? storyDiagnosisId;

  /// 0–3 focus-relative comparison chips; empty when history is thin.
  final List<SwimComparisonChip> chips;

  /// Null → empty-tip escape (KPIs / charts may still render).
  final SwimPrimaryTip? primaryTip;

  final SwimSessionKpis kpis;

  /// Additional diagnoses under collapsed “More findings”.
  final List<SwimSecondaryFinding> secondaryFindings;

  bool get hasPrimaryTip => primaryTip != null;
}

class SwimComparisonChip {
  const SwimComparisonChip({
    required this.label,
    required this.deltaLabel,
    required this.direction,
  });

  final String label;
  final String deltaLabel;
  final SwimChipDirection direction;
}

enum SwimChipDirection { up, down, flat }

class SwimPrimaryTip {
  const SwimPrimaryTip({
    required this.recId,
    required this.title,
    required this.why,
    required this.sourceDiagnosisId,
  });

  final String recId;
  final String title;
  final String why;
  final String sourceDiagnosisId;
}

class SwimSecondaryFinding {
  const SwimSecondaryFinding({
    required this.diagnosisId,
    required this.title,
    required this.body,
  });

  final String diagnosisId;
  final String title;
  final String body;
}

class SwimSessionKpis {
  const SwimSessionKpis({
    this.distanceM,
    this.durationPrimaryLabel,
    this.durationHint,
    this.avgPaceSecPer100m,
    this.avgSwolf,
    this.avgHr,
    this.maxHr,
  });

  final int? distanceM;
  final String? durationPrimaryLabel;
  final String? durationHint;
  final int? avgPaceSecPer100m;
  final int? avgSwolf;
  final int? avgHr;
  final int? maxHr;
}

/// Optional locked in-session HR KPIs — computed outside the builder.
class SwimLockedHrKpis {
  const SwimLockedHrKpis({required this.avgBpm, required this.maxBpm});

  final int avgBpm;
  final int maxBpm;
}

/// Coverage-only / non-tip session diagnosis ids (never primary tip).
const Set<String> kSwimCoverageOnlyDiagnosisIds = {
  'insufficient_intervals',
  'length_semantics_open',
  'no_strong_signal',
};

/// Default tip priority among session diagnoses (lower = wins).
const Map<String, int> kSwimTipDiagnosisPriority = {
  'fatigue_onset': 0,
  'efficiency_decline': 1,
  'pacing_uneven': 2,
  'pacing_steady': 3,
  'efficiency_improve': 4,
};

/// Lookback window for focus-relative pool chips (comparable type-6 swims).
const int kSwimChipLookbackPoolSessions = 10;

/// Build athlete insight from invent-guarded session truth + session diagnoses.
///
/// [sessionDiagnoses] must already be scoped to the invent-guarded lap set
/// (exclude `trend_*` from tip ranking — pass session list only, or trends will
/// be ignored for tip selection).
SwimSessionInsight buildSwimSessionInsight({
  required CanonicalSwimSession focus,
  required List<SwimLapMetrics> inventGuardedLaps,
  required List<SwimDiagnosis> sessionDiagnoses,
  required List<CanonicalSwimSession> recentHistory,
  SwimLockedHrKpis? lockedHr,
}) {
  final winning = _selectWinningSessionDiagnosis(sessionDiagnoses);
  final story = _storyFor(winning, focus: focus, laps: inventGuardedLaps);
  final tip = _primaryTipFor(winning, sessionDiagnoses);
  final chips = _focusRelativeChips(
    focus: focus,
    history: recentHistory,
  );
  final kpis = _buildKpis(
    focus: focus,
    laps: inventGuardedLaps,
    lockedHr: lockedHr,
  );
  final secondaries = _secondaryFindings(
    sessionDiagnoses,
    winningId: winning?.id,
  );

  return SwimSessionInsight(
    story: story,
    storyDiagnosisId: winning?.id,
    chips: chips,
    primaryTip: tip,
    kpis: kpis,
    secondaryFindings: secondaries,
  );
}

SwimDiagnosis? _selectWinningSessionDiagnosis(List<SwimDiagnosis> diagnoses) {
  final tippable = diagnoses
      .where((d) => !d.id.startsWith('trend_'))
      .where((d) => !kSwimCoverageOnlyDiagnosisIds.contains(d.id))
      .toList();
  if (tippable.isEmpty) return null;

  tippable.sort((a, b) {
    final pa = kSwimTipDiagnosisPriority[a.id] ?? 50;
    final pb = kSwimTipDiagnosisPriority[b.id] ?? 50;
    return pa.compareTo(pb);
  });
  return tippable.first;
}

String _storyFor(
  SwimDiagnosis? winning, {
  required CanonicalSwimSession focus,
  required List<SwimLapMetrics> laps,
}) {
  if (winning != null) {
    return _athleteStoryCopy[winning.id] ?? _fallbackStoryFromDiagnosis(winning);
  }
  if (laps.length < 2) {
    return 'Short session — not enough paced intervals for a coaching tip.';
  }
  if (focus.type == 8) {
    return 'Open-water effort logged — coaching narratives stay light when '
        'interval evidence is thin.';
  }
  return 'Session logged — not enough interval signal for a coaching tip yet.';
}

String _fallbackStoryFromDiagnosis(SwimDiagnosis d) {
  // Strip pipeline tone; keep athlete-facing summary when no catalog story.
  final s = d.summary.trim();
  if (s.isEmpty) return d.title;
  return s;
}

const Map<String, String> _athleteStoryCopy = {
  'fatigue_onset':
      'Efficient early, then pace and SWOLF slipped later in the set.',
  'efficiency_decline':
      'Stroke efficiency cost rose as the set wore on.',
  'pacing_uneven':
      'Interval times swung more than a controlled set — pacing was uneven.',
  'pacing_steady':
      'Pace held through the main set — a controlled, steady swim.',
  'efficiency_improve':
      'Efficiency improved through the set — SWOLF trended better late.',
};

SwimPrimaryTip? _primaryTipFor(
  SwimDiagnosis? winning,
  List<SwimDiagnosis> sessionDiagnoses,
) {
  if (winning == null) return null;
  final recs = recommendationsForDiagnoses([winning]);
  if (recs.isEmpty) {
    // Steady / improve may map via keep_steady_load which also lists no_strong_signal.
    final fallback = recommendationsForDiagnoses(sessionDiagnoses)
        .where((r) => r.sourceDiagnosisIds.contains(winning.id))
        .toList();
    if (fallback.isEmpty) return null;
    final r = fallback.first;
    return SwimPrimaryTip(
      recId: r.id,
      title: r.title,
      why: _athleteWhy(r),
      sourceDiagnosisId: winning.id,
    );
  }
  final r = recs.first;
  return SwimPrimaryTip(
    recId: r.id,
    title: r.title,
    why: _athleteWhy(r),
    sourceDiagnosisId: winning.id,
  );
}

String _athleteWhy(SwimRecommendation r) {
  // Prefer catalog detail stripped of bible / metric jargon — detail is already
  // athlete-facing in the allow-list; drop trailing bible-ish clauses if any.
  return r.detail.trim();
}

List<SwimSecondaryFinding> _secondaryFindings(
  List<SwimDiagnosis> diagnoses, {
  required String? winningId,
}) {
  final out = <SwimSecondaryFinding>[];
  for (final d in diagnoses) {
    if (d.id == winningId) continue;
    if (d.id.startsWith('trend_')) continue;
    if (kSwimCoverageOnlyDiagnosisIds.contains(d.id) &&
        d.id == 'length_semantics_open') {
      // Quiet coverage — omit from athlete More findings.
      continue;
    }
    if (d.id == 'insufficient_intervals' || d.id == 'no_strong_signal') {
      continue;
    }
    out.add(
      SwimSecondaryFinding(
        diagnosisId: d.id,
        title: d.title,
        body: d.summary,
      ),
    );
  }
  return out;
}

List<SwimComparisonChip> _focusRelativeChips({
  required CanonicalSwimSession focus,
  required List<CanonicalSwimSession> history,
}) {
  // Open-water v1: omit chips when thin / no strong OW baseline.
  if (focus.type == 8) return const [];

  final pool = focus.poolLengthM;
  if (pool == null || pool <= 0) return const [];

  final poolPeers = history
      .where((s) => s.type == 6)
      .where((s) => s.poolLengthM != null && s.poolLengthM == pool)
      .where((s) => s.workoutNumber != focus.workoutNumber)
      .toList()
    ..sort((a, b) => b.startTime.compareTo(a.startTime));

  if (poolPeers.isEmpty) return const [];

  // Lookback: last N comparable pool swims by recency, then pick prior older
  // than focus (or most recent peer if focus not in history order).
  final window = poolPeers.take(kSwimChipLookbackPoolSessions).toList();
  CanonicalSwimSession? prior;
  for (final s in window) {
    if (s.startTime < focus.startTime) {
      prior = s;
      break;
    }
  }
  prior ??= window.isEmpty ? null : window.first;
  if (prior == null) return const [];

  // Need ≥2 comparable in the broader sense: focus + prior.
  final chips = <SwimComparisonChip>[];

  final focusPace = focus.p0.movingAvgPaceSecPer100m ?? focus.p0.avgPaceSecPer100m;
  final priorPace = prior.p0.movingAvgPaceSecPer100m ?? prior.p0.avgPaceSecPer100m;
  if (focusPace != null && priorPace != null && priorPace > 0) {
    final delta = focusPace - priorPace;
    chips.add(
      SwimComparisonChip(
        label: 'Pace',
        deltaLabel: _signedSecLabel(delta, suffix: 's/100'),
        direction: delta > 1
            ? SwimChipDirection.down
            : delta < -1
                ? SwimChipDirection.up
                : SwimChipDirection.flat,
      ),
    );
  }

  final focusSwolf = focus.p0.avgSwolf;
  final priorSwolf = prior.p0.avgSwolf;
  if (focusSwolf != null && priorSwolf != null) {
    final delta = focusSwolf - priorSwolf;
    chips.add(
      SwimComparisonChip(
        label: 'SWOLF',
        deltaLabel: delta == 0 ? 'same' : _signedIntLabel(delta),
        direction: delta > 1
            ? SwimChipDirection.down
            : delta < -1
                ? SwimChipDirection.up
                : SwimChipDirection.flat,
      ),
    );
  }

  final focusDist = focus.distanceM;
  final priorDist = prior.distanceM;
  if (focusDist != null && priorDist != null && priorDist > 0) {
    final delta = focusDist - priorDist;
    final pct = (delta / priorDist) * 100.0;
    chips.add(
      SwimComparisonChip(
        label: 'Volume',
        deltaLabel: delta.abs() < priorDist * 0.05
            ? 'same'
            : '${delta >= 0 ? '+' : ''}${delta}m',
        direction: pct > 5
            ? SwimChipDirection.up
            : pct < -5
                ? SwimChipDirection.down
                : SwimChipDirection.flat,
      ),
    );
  }

  if (chips.length > 3) return chips.take(3).toList();
  return chips;
}

String _signedSecLabel(int delta, {required String suffix}) {
  if (delta == 0) return 'same';
  final sign = delta > 0 ? '+' : '';
  return '$sign$delta$suffix';
}

String _signedIntLabel(int delta) {
  final sign = delta > 0 ? '+' : '';
  return '$sign$delta';
}

SwimSessionKpis _buildKpis({
  required CanonicalSwimSession focus,
  required List<SwimLapMetrics> laps,
  SwimLockedHrKpis? lockedHr,
}) {
  final distance = _distanceFromLaps(laps) ?? focus.distanceM;
  final movingSec = _movingSecFromLaps(laps);
  final durationSec = focus.durationSec;
  String? primary;
  String? hint;
  if (movingSec != null && movingSec > 0 && movingSec <= durationSec) {
    primary = _fmtDur(movingSec);
    final rest = durationSec - movingSec;
    if (rest > 0) {
      hint = 'swim · ${_fmtDur(rest)} rest';
    }
  } else if (durationSec > 0) {
    primary = _fmtDur(durationSec);
  }

  final paced = laps
      .map((l) => l.paceSecPer100m)
      .whereType<int>()
      .where((p) => p > 0)
      .toList();
  final avgPace = paced.isEmpty
      ? (focus.p0.movingAvgPaceSecPer100m ?? focus.p0.avgPaceSecPer100m)
      : (paced.reduce((a, b) => a + b) / paced.length).round();

  final swolfs = laps.map((l) => l.swolf).whereType<int>().toList();
  final avgSwolf = swolfs.isEmpty
      ? focus.p0.avgSwolf
      : (swolfs.reduce((a, b) => a + b) / swolfs.length).round();

  return SwimSessionKpis(
    distanceM: distance,
    durationPrimaryLabel: primary,
    durationHint: hint,
    avgPaceSecPer100m: avgPace,
    avgSwolf: avgSwolf,
    avgHr: lockedHr?.avgBpm,
    maxHr: lockedHr?.maxBpm,
  );
}

int? _distanceFromLaps(List<SwimLapMetrics> laps) {
  var sum = 0;
  var any = false;
  for (final l in laps) {
    if (l.distanceM != null && l.distanceM! > 0) {
      sum += l.distanceM!;
      any = true;
    }
  }
  return any ? sum : null;
}

int? _movingSecFromLaps(List<SwimLapMetrics> laps) {
  var sum = 0;
  var any = false;
  for (final l in laps) {
    if (l.durationSec != null && l.durationSec! > 0) {
      sum += l.durationSec!;
      any = true;
    }
  }
  return any ? sum : null;
}

String _fmtDur(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
