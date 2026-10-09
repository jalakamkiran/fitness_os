import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/in_session_hr_lock.dart';

/// Lookback window for pool history used in baseline estimation.
const baselineHistoryDays = 90;

/// Minimum usable pool type-6 sessions in [baselineHistoryDays] for a
/// history-trusted baseline (no forced guided test).
const baselineSufficientSessionCount = 3;

/// Wall pace slower than this (s/100 m) is treated as rest-heavy / not a
/// continuous capacity signal without athlete confirm (~4:00/100 m).
const restHeavyPaceSecPer100m = 240;

/// Distance tolerance when matching ~200 m / ~400 m CSS efforts.
const cssDistanceToleranceM = 25;

/// Prescription returned by [BaselineResolver.prescribeGuidedTest].
class GuidedTestPrescription {
  const GuidedTestPrescription({
    required this.continuousDistanceM,
    required this.includeCssProtocol,
    this.css400DistanceM = 400,
    this.css200DistanceM = 200,
  });

  /// Non-stop continuous swim distance at/near current capacity.
  final int continuousDistanceM;

  /// When true, include a 400/200 CSS time-trial protocol after the
  /// continuous swim (pace-goal path).
  final bool includeCssProtocol;

  final int css400DistanceM;
  final int css200DistanceM;
}

/// Estimates continuous-distance capacity and optional CSS pace from pool
/// type-6 history; drives guided test or self-report when thin.
///
/// Pure Dart — no Flutter, no Coach imports.
class BaselineResolver {
  /// Resolve a [Baseline] from recent canonical swims.
  ///
  /// Only [poolSwimWorkoutType] (6) sessions with usable [distanceM] inside
  /// the last [baselineHistoryDays] contribute. Open water (8) is ignored.
  Baseline resolve({
    required List<CanonicalSwimSession> sessions,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now().toUtc();
    final cutoffUnix =
        now.toUtc().subtract(const Duration(days: baselineHistoryDays));
    final cutoffSec = cutoffUnix.millisecondsSinceEpoch ~/ 1000;

    final recentPool = <CanonicalSwimSession>[];
    var sawOpenWaterInWindow = false;

    for (final s in sessions) {
      if (s.startTime < cutoffSec) continue;
      if (s.type == openWaterSwimWorkoutType) {
        sawOpenWaterInWindow = true;
        continue;
      }
      if (s.type != poolSwimWorkoutType) continue;
      final d = s.distanceM;
      if (d == null || d <= 0) continue;
      recentPool.add(s);
    }

    if (recentPool.isEmpty) {
      return Baseline(
        capacityDistanceM: 0,
        confidence: BaselineConfidence.insufficient,
        reason: sawOpenWaterInWindow
            ? BaselineReason.openWaterOnly
            : BaselineReason.emptyHistory,
        guidedTestRequired: true,
      );
    }

    final usable = <CanonicalSwimSession>[];
    final restHeavy = <CanonicalSwimSession>[];
    for (final s in recentPool) {
      if (_isRestHeavy(s)) {
        restHeavy.add(s);
      } else {
        usable.add(s);
      }
    }

    if (usable.isEmpty) {
      return Baseline(
        capacityDistanceM: 0,
        confidence: BaselineConfidence.insufficient,
        reason: BaselineReason.restHeavyUnconfirmed,
        guidedTestRequired: true,
        sourceWorkoutNumbers:
            restHeavy.map((s) => s.workoutNumber).toList(growable: false),
      );
    }

    usable.sort((a, b) => (b.distanceM ?? 0).compareTo(a.distanceM ?? 0));
    final capacity = usable.first.distanceM!;
    final sourceNumbers =
        usable.map((s) => s.workoutNumber).toList(growable: false);
    final css = _estimateCssPaceSecPer100(usable);

    if (usable.length < baselineSufficientSessionCount) {
      return Baseline(
        capacityDistanceM: capacity,
        cssPaceSecPer100: css,
        confidence: BaselineConfidence.low,
        reason: BaselineReason.sparseHistory,
        guidedTestRequired: true,
        sourceWorkoutNumbers: sourceNumbers,
      );
    }

    final confidence = (usable.length >= 5 || css != null)
        ? BaselineConfidence.high
        : BaselineConfidence.medium;

    return Baseline(
      capacityDistanceM: capacity,
      cssPaceSecPer100: css,
      confidence: confidence,
      reason: BaselineReason.richHistory,
      guidedTestRequired: false,
      sourceWorkoutNumbers: sourceNumbers,
    );
  }

  /// Last-resort self-report when guided test is skipped or unavailable.
  static Baseline selfReport({
    required int capacityDistanceM,
    double? cssPaceSecPer100,
  }) {
    return Baseline(
      capacityDistanceM: capacityDistanceM,
      cssPaceSecPer100: cssPaceSecPer100,
      confidence: BaselineConfidence.low,
      reason: BaselineReason.selfReported,
      guidedTestRequired: false,
      selfReported: true,
    );
  }

  /// Simple continuous-swim prescription at/near [current] capacity, plus
  /// optional 400/200 CSS protocol when a pace goal is present.
  GuidedTestPrescription prescribeGuidedTest({
    required Baseline current,
    bool paceGoalPresent = false,
  }) {
    final capacity = current.capacityDistanceM;
    final continuous = capacity <= 0
        ? 400
        : _roundTo50(_clamp(capacity, min: 200, max: capacity + 200));

    return GuidedTestPrescription(
      continuousDistanceM: continuous,
      includeCssProtocol: paceGoalPresent,
    );
  }

  static bool _isRestHeavy(CanonicalSwimSession s) {
    final d = s.distanceM;
    if (d == null || d <= 0 || s.durationSec <= 0) return true;
    final wallPace = (s.durationSec * 100) / d;
    return wallPace > restHeavyPaceSecPer100m;
  }

  /// CSS pace per 100 m = (T400 − T200) / 2 when both effort distances exist
  /// within ±[cssDistanceToleranceM].
  static double? _estimateCssPaceSecPer100(
    List<CanonicalSwimSession> usable,
  ) {
    CanonicalSwimSession? best200;
    CanonicalSwimSession? best400;
    var best200Delta = 1 << 30;
    var best400Delta = 1 << 30;

    for (final s in usable) {
      final d = s.distanceM!;
      final d200 = (d - 200).abs();
      if (d200 <= cssDistanceToleranceM && d200 < best200Delta) {
        best200 = s;
        best200Delta = d200;
      }
      final d400 = (d - 400).abs();
      if (d400 <= cssDistanceToleranceM && d400 < best400Delta) {
        best400 = s;
        best400Delta = d400;
      }
    }

    if (best200 == null || best400 == null) return null;
    if (identical(best200, best400)) return null;

    final t400 = best400.durationSec.toDouble();
    final t200 = best200.durationSec.toDouble();
    if (t400 <= t200) return null;

    final css = (t400 - t200) / 2.0;
    if (css <= 0 || css > restHeavyPaceSecPer100m) return null;
    return css;
  }

  static int _roundTo50(int m) => ((m + 25) ~/ 50) * 50;

  static int _clamp(int v, {required int min, required int max}) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }
}
