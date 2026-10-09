import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/program_planner.dart';
import 'package:fitness_os/features/workout_history/domain/in_session_hr_lock.dart';

/// Manual athlete action on a chore (habit layer only — no milestone slip).
enum ManualChoreAction {
  doneManual,
  adjusted,
  skippedExcused,
  skippedOther,
  moved,
}

/// Pool swim candidate for chore/proof matching.
///
/// [startTime] is Unix **seconds** (same convention as CanonicalSwimSession).
/// Local calendar day is derived via the device local timezone.
class PoolSwimCandidate {
  const PoolSwimCandidate({
    required this.workoutNumber,
    required this.startTime,
    required this.type,
    required this.durationSec,
    this.distanceM,
  });

  final int workoutNumber;

  /// Unix seconds since epoch (not milliseconds).
  final int startTime;
  final int type;
  final int? distanceM;
  final int durationSec;

  /// Local YYYY-MM-DD derived from [startTime].
  String get localDayIso {
    final local = DateTime.fromMillisecondsSinceEpoch(
      startTime * 1000,
      isUtc: false,
    );
    return _isoDate(local);
  }
}

/// One auto-matched chore + the swim that satisfied it.
class ChoreMatchResult {
  const ChoreMatchResult({
    required this.chore,
    required this.swim,
  });

  /// Updated session in [ChoreState.doneSynced] with workout bind + judged metrics.
  final ChoreSession chore;
  final PoolSwimCandidate swim;
}

/// Proof evaluation against a milestone (planner slip is application-layer).
class ProofMatchResult {
  const ProofMatchResult({
    required this.outcome,
    required this.milestone,
    required this.swim,
    required this.continuousConfirmed,
    this.judgedDistanceM,
  });

  final ProofOutcome outcome;
  final Milestone milestone;
  final PoolSwimCandidate swim;
  final bool continuousConfirmed;
  final int? judgedDistanceM;
}

/// Pure matcher: returns match results; application layer calls store/planner.
class ChoreMatcher {
  /// Auto-match pool (type 6) swims to due/scheduled/lapsed chores.
  ///
  /// Rules:
  /// - Type [poolSwimWorkoutType] (6) only — OW (8) never matches.
  /// - Same local day as the chore, or lapsed rematch while [asOf] is still
  ///   within [lateSyncWindow] after the chore day.
  /// - Distance within [distanceToleranceFraction] of [ChoreSession.targetDistanceM]
  ///   or the main-block distance.
  /// - Each swim and each chore matched at most once.
  List<ChoreMatchResult> matchChores({
    required Program program,
    required List<PoolSwimCandidate> swims,
    required DateTime asOf,
    Duration lateSyncWindow = const Duration(hours: 72),
    double distanceToleranceFraction = 0.05,
  }) {
    final poolSwims = swims
        .where((s) => s.type == poolSwimWorkoutType && s.distanceM != null)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final openChores = program.chores
        .where(_isMatchableState)
        .toList()
      ..sort((a, b) => a.dayIso.compareTo(b.dayIso));

    final usedChoreIds = <String>{};
    final results = <ChoreMatchResult>[];

    for (final swim in poolSwims) {
      ChoreSession? best;
      var bestDelta = 1 << 30;

      for (final chore in openChores) {
        if (usedChoreIds.contains(chore.id)) continue;
        if (!_dayEligible(chore, swim, asOf, lateSyncWindow)) continue;
        if (!_distanceWithinTolerance(
          chore,
          swim.distanceM!,
          distanceToleranceFraction,
        )) {
          continue;
        }

        final delta = _distanceDelta(chore, swim.distanceM!);
        if (delta < bestDelta) {
          bestDelta = delta;
          best = chore;
        }
      }

      if (best == null) continue;
      usedChoreIds.add(best.id);

      final updated = best.copyWith(
        state: ChoreState.doneSynced,
        matchedWorkoutNumber: swim.workoutNumber,
        matchedStartTime: swim.startTime,
        judgedDistanceM: swim.distanceM,
        judgedDurationSec: swim.durationSec,
        completedAtMs: asOf.millisecondsSinceEpoch,
      );
      results.add(ChoreMatchResult(chore: updated, swim: swim));
    }

    return results;
  }

  /// Evaluate a proof swim against [milestone].
  ///
  /// Continuity is not computable from lap rows in v1, so [continuousConfirmed]
  /// is required for pass / near-pass. Distance ≥ target → pass; ≥ [nearPassFraction]
  /// → nearPass; else fail. Non-pool types always fail.
  ProofMatchResult matchProof({
    required Milestone milestone,
    required PoolSwimCandidate swim,
    required bool continuousConfirmed,
    double nearPassFraction = 0.90,
  }) {
    final distance = swim.distanceM;
    if (swim.type != poolSwimWorkoutType || distance == null) {
      return ProofMatchResult(
        outcome: ProofOutcome.fail,
        milestone: milestone,
        swim: swim,
        continuousConfirmed: continuousConfirmed,
        judgedDistanceM: distance,
      );
    }

    if (!continuousConfirmed) {
      return ProofMatchResult(
        outcome: ProofOutcome.fail,
        milestone: milestone,
        swim: swim,
        continuousConfirmed: false,
        judgedDistanceM: distance,
      );
    }

    final target = milestone.targetDistanceM;
    final ProofOutcome outcome;
    if (distance >= target) {
      outcome = ProofOutcome.pass;
    } else if (distance >= (target * nearPassFraction).round()) {
      outcome = ProofOutcome.nearPass;
    } else {
      outcome = ProofOutcome.fail;
    }

    return ProofMatchResult(
      outcome: outcome,
      milestone: milestone,
      swim: swim,
      continuousConfirmed: true,
      judgedDistanceM: distance,
    );
  }

  /// Apply a manual habit action. Does **not** emit milestone slip outcomes.
  ChoreSession applyManual({
    required ChoreSession chore,
    required ManualChoreAction action,
    SkipReason? skipReason,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final completedAt = now.millisecondsSinceEpoch;

    switch (action) {
      case ManualChoreAction.doneManual:
        return chore.copyWith(
          state: ChoreState.doneManual,
          completedAtMs: completedAt,
        );
      case ManualChoreAction.adjusted:
        return chore.copyWith(
          state: ChoreState.adjusted,
          completedAtMs: completedAt,
        );
      case ManualChoreAction.skippedExcused:
        return chore.copyWith(
          state: ChoreState.skippedExcused,
          skipReason: skipReason ?? SkipReason.other,
          completedAtMs: completedAt,
        );
      case ManualChoreAction.skippedOther:
        return chore.copyWith(
          state: ChoreState.skippedOther,
          skipReason: skipReason ?? SkipReason.other,
          completedAtMs: completedAt,
        );
      case ManualChoreAction.moved:
        return chore.copyWith(
          state: ChoreState.moved,
          completedAtMs: completedAt,
        );
    }
  }

  bool _isMatchableState(ChoreSession chore) {
    switch (chore.state) {
      case ChoreState.scheduled:
      case ChoreState.due:
      case ChoreState.lapsed:
        return true;
      case ChoreState.doneSynced:
      case ChoreState.doneManual:
      case ChoreState.adjusted:
      case ChoreState.moved:
      case ChoreState.skippedExcused:
      case ChoreState.skippedOther:
      case ChoreState.superseded:
        return false;
    }
  }

  bool _dayEligible(
    ChoreSession chore,
    PoolSwimCandidate swim,
    DateTime asOf,
    Duration lateSyncWindow,
  ) {
    if (swim.localDayIso != chore.dayIso) return false;

    final choreDay = _parseIso(chore.dayIso);
    if (choreDay == null) return false;

    // Same local day required; [asOf] must still be within the late-sync
    // window measured from the chore calendar day (Strava-style restore).
    final deadline = choreDay.add(lateSyncWindow);
    if (asOf.isAfter(deadline)) return false;

    // Reject matching a future chore day before that day begins.
    final asOfDay = DateTime(asOf.year, asOf.month, asOf.day);
    if (asOfDay.isBefore(choreDay)) return false;

    return true;
  }

  bool _distanceWithinTolerance(
    ChoreSession chore,
    int distanceM,
    double fraction,
  ) {
    for (final target in _distanceTargets(chore)) {
      if (target <= 0) continue;
      final tol = target * fraction;
      if ((distanceM - target).abs() <= tol) return true;
    }
    return false;
  }

  int _distanceDelta(ChoreSession chore, int distanceM) {
    var best = 1 << 30;
    for (final target in _distanceTargets(chore)) {
      final d = (distanceM - target).abs();
      if (d < best) best = d;
    }
    return best;
  }

  List<int> _distanceTargets(ChoreSession chore) {
    final targets = <int>[chore.targetDistanceM];
    for (final block in chore.blocks) {
      if (block.part == 'main') {
        targets.add(block.distanceM);
      }
    }
    return targets;
  }
}

String _isoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime? _parseIso(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}
