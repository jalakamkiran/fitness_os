import 'dart:math' as math;

import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/rules_pack/formulas.dart';
import 'package:fitness_os/features/programs/domain/rules_pack/patterns.dart';
import 'package:fitness_os/features/programs/domain/rules_pack/rules_pack.dart';

/// Proof attempt outcome used to slip or advance the milestone ladder.
///
/// Chore miss does **not** call slip — only proof / delay / pause paths.
enum ProofOutcome {
  pass,
  nearPass,
  fail,
  delay,
}

/// Deterministic generator: capacity ladder + weekly WU/main/CD chores.
///
/// Pure Dart — no Flutter, no Coach imports.
class ProgramPlanner {
  /// Build a pool-only program from intake + baseline.
  Program plan({
    required ProgramIntake intake,
    required Baseline baseline,
    required DateTime startDate,
    String? id,
  }) {
    final programId = id ?? _idFrom(startDate);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final sessionsPerWeek = intake.sessionsPerWeek.clamp(2, 5);
    final horizonWeeks = intake.horizonWeeks < 1 ? 1 : intake.horizonWeeks;

    final rungDistances = _capacityLadder(
      capacityM: baseline.capacityDistanceM,
      goalM: intake.goalDistanceM,
      step: rungStepDefault,
    );

    final blockWeeks = rungBlockWeeks(sessionsPerWeek);
    final milestones = <Milestone>[];
    var cursor = start;
    for (var i = 0; i < rungDistances.length; i++) {
      // Place proof near end of block (day after a mid-week rest pattern).
      final proofDay = cursor.add(Duration(days: blockWeeks * 7 - 1));
      final iso = _iso(proofDay);
      milestones.add(
        Milestone(
          id: '${programId}_ms_$i',
          index: i,
          targetDistanceM: rungDistances[i],
          plannedDateIso: iso,
          forecastDateIso: iso,
          status: MilestoneStatus.upcoming,
        ),
      );
      cursor = proofDay.add(const Duration(days: 1));
    }

    final warning = _feasibilityWarning(
      intake: intake,
      baseline: baseline,
    );

    final forecast = _goalForecast(
      start: start,
      milestones: milestones,
      intake: intake,
      baseline: baseline,
    );

    final chores = _buildChores(
      programId: programId,
      start: start,
      horizonWeeks: horizonWeeks,
      sessionsPerWeek: sessionsPerWeek,
      intake: intake,
      baseline: baseline,
      milestones: milestones,
      volumeGrowthCap: weeklyVolumeGrowthDefault,
    );

    return Program(
      id: programId,
      intake: intake,
      status: ProgramStatus.active,
      createdAtMs: start.millisecondsSinceEpoch,
      rulesPackVersion: rulesPackVersion,
      schemaVersion: Program.currentSchemaVersion,
      baseline: baseline,
      milestones: milestones,
      chores: chores,
      feasibilityWarning: warning,
      goalForecastEarliestIso: forecast.$1,
      goalForecastLikelyIso: forecast.$2,
      goalForecastLatestIso: forecast.$3,
      poolOnly: true,
      activatedAtMs: start.millisecondsSinceEpoch,
    );
  }

  /// Slip milestone dates after proof fail / near-pass / delay / pause family.
  ///
  /// Pass marks the rung passed and advances. Near-pass keeps the rung and
  /// slips ~7 days. Fail slips ~7–14 days and regenerates upcoming chores with
  /// weekly volume bump ≤10%. Delay slips ~7 days without changing the rung.
  Program applyProofOutcome(
    Program program, {
    required String milestoneId,
    required ProofOutcome outcome,
    DateTime? asOf,
  }) {
    final idx = program.milestones.indexWhere((m) => m.id == milestoneId);
    if (idx < 0) return program;

    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final milestones = List<Milestone>.from(program.milestones);
    final target = milestones[idx];

    switch (outcome) {
      case ProofOutcome.pass:
        milestones[idx] = target.copyWith(
          status: MilestoneStatus.passed,
          passedAtIso: _iso(today),
          attemptCount: target.attemptCount + 1,
          forecastDateIso: _iso(today),
        );
      case ProofOutcome.nearPass:
        milestones[idx] = target.copyWith(
          status: MilestoneStatus.nearPass,
          attemptCount: target.attemptCount + 1,
          slipDays: target.slipDays + nearPassSlipDays,
          notes: 'Near-pass: keep rung, slip $nearPassSlipDays days',
        );
        _slipFrom(milestones, idx, nearPassSlipDays);
      case ProofOutcome.fail:
        milestones[idx] = target.copyWith(
          status: MilestoneStatus.failed,
          attemptCount: target.attemptCount + 1,
          slipDays: target.slipDays + failSlipDays,
          notes: 'Fail: slip $failSlipDays days; next volume bump ≤10%',
        );
        _slipFrom(milestones, idx, failSlipDays);
      case ProofOutcome.delay:
        milestones[idx] = target.copyWith(
          status: MilestoneStatus.delayed,
          attemptCount: target.attemptCount + 1,
          slipDays: target.slipDays + delaySlipDays,
          notes: 'Delay: slip $delaySlipDays days',
        );
        _slipFrom(milestones, idx, delaySlipDays);
    }

    final start = _parseIso(
          program.chores.isNotEmpty
              ? program.chores.first.dayIso
              : program.milestones.first.plannedDateIso,
        ) ??
        today;

    final forecast = _goalForecast(
      start: start,
      milestones: milestones,
      intake: program.intake,
      baseline: program.baseline ??
          const Baseline(
            capacityDistanceM: 0,
            confidence: BaselineConfidence.insufficient,
            reason: BaselineReason.emptyHistory,
          ),
    );

    var chores = program.chores;
    if (outcome == ProofOutcome.fail ||
        outcome == ProofOutcome.nearPass ||
        outcome == ProofOutcome.delay) {
      // Shift future chore days with the same slip; on fail, rebuild with
      // volume growth capped at weeklyVolumeGrowthMax (≤10%).
      final slipDays = switch (outcome) {
        ProofOutcome.nearPass => nearPassSlipDays,
        ProofOutcome.fail => failSlipDays,
        ProofOutcome.delay => delaySlipDays,
        ProofOutcome.pass => 0,
      };
      if (outcome == ProofOutcome.fail) {
        final capacity = program.baseline?.capacityDistanceM ??
            program.intake.goalDistanceM;
        chores = _buildChores(
          programId: program.id,
          start: start,
          horizonWeeks: program.intake.horizonWeeks,
          sessionsPerWeek: program.intake.sessionsPerWeek.clamp(2, 5),
          intake: program.intake,
          baseline: program.baseline ??
              Baseline(
                capacityDistanceM: capacity,
                confidence: BaselineConfidence.low,
                reason: BaselineReason.selfReported,
              ),
          milestones: milestones,
          volumeGrowthCap: weeklyVolumeGrowthMax,
          // After fail, seed slightly flatter growth and smaller key sessions.
          afterFail: true,
        );
      } else {
        chores = [
          for (final c in program.chores)
            if (_parseIso(c.dayIso) != null &&
                !_isBeforeMilestoneDay(c.dayIso, target.plannedDateIso))
              c.copyWith(
                dayIso: _iso(
                  _parseIso(c.dayIso)!.add(Duration(days: slipDays)),
                ),
              )
            else
              c,
        ];
      }
    }

    return program.copyWith(
      milestones: milestones,
      chores: chores,
      goalForecastEarliestIso: forecast.$1,
      goalForecastLikelyIso: forecast.$2,
      goalForecastLatestIso: forecast.$3,
    );
  }

  // --- Ladder --------------------------------------------------------------

  List<int> _capacityLadder({
    required int capacityM,
    required int goalM,
    required double step,
  }) {
    final goal = roundToPoolStep(goalM);
    var current = capacityM < distanceRoundM
        ? distanceRoundM
        : roundToPoolStep(capacityM);
    if (current >= goal) {
      // Already at/above goal — still schedule a confirmation proof at goal.
      return [goal];
    }
    final rungs = <int>[];
    var guard = 0;
    while (current < goal && guard < 32) {
      final next = nextCapacityRung(
        currentM: current,
        goalM: goal,
        step: step,
      );
      rungs.add(next);
      current = next;
      guard++;
    }
    return rungs;
  }

  // --- Roles ---------------------------------------------------------------

  /// Weekly session roles by sessions/week (algorithms research §6.4).
  static List<ChoreRole> rolesForSessionsPerWeek(int n) {
    switch (n) {
      case 2:
        return const [ChoreRole.endurance, ChoreRole.quality];
      case 3:
        return const [
          ChoreRole.endurance,
          ChoreRole.quality,
          ChoreRole.technique,
        ];
      case 4:
        return const [
          ChoreRole.endurance,
          ChoreRole.quality,
          ChoreRole.technique,
          ChoreRole.easy,
        ];
      default:
        // 5 (and any higher clamped to 5 by caller)
        return const [
          ChoreRole.endurance,
          ChoreRole.quality,
          ChoreRole.technique,
          ChoreRole.easy,
          ChoreRole.recovery,
        ];
    }
  }

  // --- Chores --------------------------------------------------------------

  List<ChoreSession> _buildChores({
    required String programId,
    required DateTime start,
    required int horizonWeeks,
    required int sessionsPerWeek,
    required ProgramIntake intake,
    required Baseline baseline,
    required List<Milestone> milestones,
    required double volumeGrowthCap,
    bool afterFail = false,
  }) {
    final roles = rolesForSessionsPerWeek(sessionsPerWeek);
    final dayOffsets = _sessionDayOffsets(sessionsPerWeek);
    final seedTotal = _seedSessionTotalM(
      goalM: intake.goalDistanceM,
      capacityM: baseline.capacityDistanceM,
      afterFail: afterFail,
    );

    final chores = <ChoreSession>[];
    var weekVolume = seedTotal * sessionsPerWeek;
    final proofDays = {
      for (final m in milestones)
        if (m.status != MilestoneStatus.passed) m.forecastDateIso: m,
    };

    for (var w = 0; w < horizonWeeks; w++) {
      final isDeload =
          !afterFail && w > 0 && (w + 1) % deloadEveryWeeks == 0;
      if (w > 0 && !isDeload) {
        final growth = volumeGrowthCap < weeklyVolumeGrowthDefault
            ? volumeGrowthCap
            : weeklyVolumeGrowthDefault;
        final capped = growth > weeklyVolumeGrowthMax
            ? weeklyVolumeGrowthMax
            : growth;
        weekVolume = (weekVolume * (1.0 + capped)).round();
      } else if (isDeload) {
        weekVolume = (weekVolume * deloadFactor).round();
      }

      final perSession = roundToPoolStep(weekVolume ~/ sessionsPerWeek);
      final weekStart = start.add(Duration(days: w * 7));

      for (var s = 0; s < roles.length; s++) {
        final day = weekStart.add(Duration(days: dayOffsets[s]));
        final dayIso = _iso(day);
        final milestone = proofDays[dayIso];
        final role = milestone != null ? ChoreRole.proof : roles[s];
        final total = role == ChoreRole.proof
            ? _proofSessionTotalM(milestone!.targetDistanceM)
            : _roleSessionTotalM(role, perSession);

        final blocks = _assembleBlocks(
          role: role,
          sessionTotalM: total,
          proofDistanceM: milestone?.targetDistanceM,
        );

        chores.add(
          ChoreSession(
            id: '${programId}_w${w}_s$s',
            programId: programId,
            dayIso: dayIso,
            role: role,
            state: ChoreState.scheduled,
            blocks: blocks,
            targetDistanceM: blocks.fold<int>(0, (a, b) => a + b.distanceM),
            focusLine: _focusLine(role, milestone?.targetDistanceM),
            milestoneId: milestone?.id,
          ),
        );
      }
    }

    // Ensure each milestone has a dedicated proof chore on its forecast day
    // when the weekly grid missed that calendar day.
    for (final m in milestones) {
      if (m.status == MilestoneStatus.passed) continue;
      final hasProof = chores.any(
        (c) => c.milestoneId == m.id && c.role == ChoreRole.proof,
      );
      if (hasProof) continue;
      final total = _proofSessionTotalM(m.targetDistanceM);
      chores.add(
        ChoreSession(
          id: '${programId}_proof_${m.index}',
          programId: programId,
          dayIso: m.forecastDateIso,
          role: ChoreRole.proof,
          state: ChoreState.scheduled,
          blocks: _assembleBlocks(
            role: ChoreRole.proof,
            sessionTotalM: total,
            proofDistanceM: m.targetDistanceM,
          ),
          targetDistanceM: total,
          focusLine: _focusLine(ChoreRole.proof, m.targetDistanceM),
          milestoneId: m.id,
        ),
      );
    }

    chores.sort((a, b) => a.dayIso.compareTo(b.dayIso));
    return chores;
  }

  int _seedSessionTotalM({
    required int goalM,
    required int capacityM,
    required bool afterFail,
  }) {
    // Prefer key-session band; dogfood 1200 → ~1440 then clamp.
    final raw = roundToPoolStep(
      ((goalM > capacityM ? goalM : capacityM) * 1.2).round(),
    );
    var total = clampInt(raw, keySessionMinM, keySessionMaxM);
    if (afterFail) {
      // Flatten: stay within support/key overlap, no jump past prior week+10%.
      total = clampInt(
        roundToPoolStep((total * 0.95).round()),
        supportSessionMinM,
        keySessionMaxM,
      );
    }
    return total;
  }

  int _roleSessionTotalM(ChoreRole role, int base) {
    switch (role) {
      case ChoreRole.endurance:
        return clampInt(base, keySessionMinM, keySessionMaxM);
      case ChoreRole.quality:
        return clampInt(
          roundToPoolStep((base * 0.95).round()),
          supportSessionMinM,
          keySessionMaxM,
        );
      case ChoreRole.technique:
        return clampInt(
          roundToPoolStep((base * 0.85).round()),
          supportSessionMinM,
          supportSessionMaxM,
        );
      case ChoreRole.easy:
      case ChoreRole.recovery:
        return clampInt(
          roundToPoolStep((base * 0.75).round()),
          supportSessionMinM,
          supportSessionMaxM,
        );
      case ChoreRole.proof:
      case ChoreRole.guidedTest:
        return base;
    }
  }

  int _proofSessionTotalM(int proofDistanceM) {
    final wu = warmUpDistanceM(proofDistanceM + 600);
    final cd = coolDownDistanceM(proofDistanceM + 600);
    // Prefer longer CD after proof (≥200).
    final cdAdj = cd < 200 ? 200 : cd;
    return wu + proofDistanceM + cdAdj;
  }

  List<ChoreBlock> _assembleBlocks({
    required ChoreRole role,
    required int sessionTotalM,
    int? proofDistanceM,
  }) {
    final wuPat = warmUpPatternFor(role);
    final cdPat = patternById('CD1');

    if (role == ChoreRole.proof && proofDistanceM != null) {
      final wu = warmUpDistanceM(sessionTotalM);
      var cd = coolDownDistanceM(sessionTotalM);
      if (cd < 200) cd = 200;
      final pre = patternById('PRE1');
      final preDist = 4 * 50 + 2 * 25; // 250
      final wuCore = wu > preDist + warmUpFloorM
          ? wu - preDist
          : warmUpFloorM;
      return [
        ChoreBlock(
          part: 'warmUp',
          label: wuPat.label,
          distanceM: wuCore,
          restGuidanceSec: wuPat.defaultRestSec,
          patternId: wuPat.id,
          effortBand: wuPat.effortBand,
        ),
        ChoreBlock(
          part: 'pre',
          label: pre.label,
          distanceM: preDist,
          restGuidanceSec: pre.defaultRestSec,
          patternId: pre.id,
          effortBand: pre.effortBand,
        ),
        ChoreBlock(
          part: 'main',
          label: 'Continuous ${proofDistanceM} m proof',
          distanceM: proofDistanceM,
          restGuidanceSec: 0,
          patternId: 'PRF1',
          effortBand: 'S',
        ),
        ChoreBlock(
          part: 'coolDown',
          label: cdPat.label,
          distanceM: cd,
          restGuidanceSec: 0,
          patternId: cdPat.id,
          effortBand: cdPat.effortBand,
        ),
      ];
    }

    final wu = warmUpDistanceM(sessionTotalM);
    final cd = coolDownDistanceM(sessionTotalM);
    final main = mainDistanceM(sessionTotalM);
    final mainPat = mainPatternFor(role);

    return [
      ChoreBlock(
        part: 'warmUp',
        label: wuPat.label,
        distanceM: wu,
        restGuidanceSec: wuPat.defaultRestSec > 0 ? wuPat.defaultRestSec : null,
        patternId: wuPat.id,
        effortBand: wuPat.effortBand,
      ),
      ChoreBlock(
        part: 'main',
        label: mainPat.label,
        distanceM: main,
        restGuidanceSec: mainPat.defaultRestSec,
        patternId: mainPat.id,
        effortBand: mainPat.effortBand,
      ),
      ChoreBlock(
        part: 'coolDown',
        label: cdPat.label,
        distanceM: cd,
        restGuidanceSec: null,
        patternId: cdPat.id,
        effortBand: cdPat.effortBand,
      ),
    ];
  }

  /// Spread sessions across the week (Mon-first local week from [start]).
  List<int> _sessionDayOffsets(int n) {
    switch (n) {
      case 2:
        return const [0, 3];
      case 3:
        return const [0, 2, 4];
      case 4:
        return const [0, 2, 4, 5];
      default:
        return const [0, 1, 3, 4, 5];
    }
  }

  String _focusLine(ChoreRole role, int? proofM) {
    switch (role) {
      case ChoreRole.endurance:
        return 'Long-rep aerobic; shrink rest toward continuous';
      case ChoreRole.quality:
        return 'One threshold / goal-pace quality set';
      case ChoreRole.technique:
        return 'Technique + easy aerobic';
      case ChoreRole.easy:
        return 'Easy aerobic volume';
      case ChoreRole.recovery:
        return 'Easy recovery swim';
      case ChoreRole.proof:
        return 'Capacity proof: ${proofM ?? '?'} m continuous';
      case ChoreRole.guidedTest:
        return 'Guided baseline / CSS test';
    }
  }

  // --- Feasibility ---------------------------------------------------------

  String? _feasibilityWarning({
    required ProgramIntake intake,
    required Baseline baseline,
  }) {
    final targetSec = intake.targetTimeSec;
    if (targetSec == null || targetSec <= 0 || intake.goalDistanceM <= 0) {
      return null;
    }

    final goalPace = targetSec * 100.0 / intake.goalDistanceM;
    final css = baseline.cssPaceSecPer100;

    // Predicted continuous pace at goal: CSS + small steady offset, or Riegel
    // from a synthetic 400 when CSS known.
    double predictedPace;
    if (css != null && css > 0) {
      // Riegel from 400 @ CSS-ish: T400 ≈ css * 4; scale to goal distance.
      final t400 = css * 4.0;
      final tPred = t400 *
          _pow(intake.goalDistanceM / 400.0, riegelExponent);
      predictedPace = tPred * 100.0 / intake.goalDistanceM;
    } else {
      // No CSS: assume needing a meaningful improvement if target is ambitious
      // relative to a recreational steady band (~2:00/100).
      predictedPace = goalPace + 8.0;
    }

    final paceGap = predictedPace - goalPace;
    if (paceGap <= 1.0) return null;

    final weeksOptimistic =
        paceGap / cssGainOptimisticSecPer100PerWeek;
    final weeksPessimistic =
        paceGap / cssGainPessimisticSecPer100PerWeek;

    if (weeksOptimistic <= intake.horizonWeeks) return null;

    final capacityWeeks = rungBlockWeeks(intake.sessionsPerWeek.clamp(2, 5));
    final monthsLo = (weeksOptimistic / 4.3).ceil();
    final monthsHi = (weeksPessimistic / 4.3).ceil();

    return 'Capacity goal (${intake.goalDistanceM} m continuous) looks '
        'realistic within ~$capacityWeeks–${capacityWeeks + 1} weeks; '
        'the time target needs roughly $monthsLo–$monthsHi months at typical '
        'CSS gains (0.3–0.5 s/100/wk). Proceed with the capacity ladder; '
        'treat the time goal as a forecast.';
  }

  // --- Forecast ------------------------------------------------------------

  /// Returns (earliest, likely, latest) ISO dates.
  (String, String, String) _goalForecast({
    required DateTime start,
    required List<Milestone> milestones,
    required ProgramIntake intake,
    required Baseline baseline,
  }) {
    DateTime capacityComplete;
    if (milestones.isEmpty) {
      capacityComplete = start.add(Duration(days: intake.horizonWeeks * 7));
    } else {
      final open = milestones.where((m) => m.status != MilestoneStatus.passed);
      final last = (open.isEmpty ? milestones : open).last;
      capacityComplete = _parseIso(last.forecastDateIso) ?? start;
    }

    var earliest = capacityComplete.add(const Duration(days: taperDaysMin));
    var likely = capacityComplete.add(const Duration(days: taperDaysMax));
    var latest = likely;

    final targetSec = intake.targetTimeSec;
    if (targetSec != null &&
        targetSec > 0 &&
        baseline.cssPaceSecPer100 != null) {
      final goalPace = targetSec * 100.0 / intake.goalDistanceM;
      final t400 = baseline.cssPaceSecPer100! * 4.0;
      final tPred =
          t400 * _pow(intake.goalDistanceM / 400.0, riegelExponent);
      final predPace = tPred * 100.0 / intake.goalDistanceM;
      final gap = predPace - goalPace;
      if (gap > 1.0) {
        final weeksOpt = gap / cssGainOptimisticSecPer100PerWeek;
        final weeksPes = gap / cssGainPessimisticSecPer100PerWeek;
        final paceEarliest =
            start.add(Duration(days: (weeksOpt * 7).ceil()));
        final paceLatest =
            start.add(Duration(days: (weeksPes * 7).ceil()));
        if (paceEarliest.isAfter(earliest)) earliest = paceEarliest;
        if (paceLatest.isAfter(latest)) latest = paceLatest;
        final midDays =
            ((paceEarliest.difference(start).inDays +
                        paceLatest.difference(start).inDays) /
                    2)
                .round();
        final paceLikely = start.add(Duration(days: midDays));
        if (paceLikely.isAfter(likely)) likely = paceLikely;
      }
    } else {
      // Widen slightly when confidence is low / no pace track.
      latest = likely.add(const Duration(days: 7));
    }

    if (likely.isBefore(earliest)) likely = earliest;
    if (latest.isBefore(likely)) latest = likely;

    return (_iso(earliest), _iso(likely), _iso(latest));
  }

  // --- Slip helpers --------------------------------------------------------

  void _slipFrom(List<Milestone> milestones, int fromIndex, int days) {
    for (var i = fromIndex; i < milestones.length; i++) {
      final m = milestones[i];
      if (m.status == MilestoneStatus.passed) continue;
      final d = _parseIso(m.forecastDateIso);
      if (d == null) continue;
      milestones[i] = m.copyWith(
        forecastDateIso: _iso(d.add(Duration(days: days))),
        slipDays: m.slipDays + (i == fromIndex ? 0 : days),
      );
    }
  }

  bool _isBeforeMilestoneDay(String dayIso, String milestonePlannedIso) {
    return dayIso.compareTo(milestonePlannedIso) < 0;
  }

  // --- Dates / ids ---------------------------------------------------------

  String _iso(DateTime d) {
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

  String _idFrom(DateTime start) {
    return 'prog_${start.millisecondsSinceEpoch}';
  }

  double _pow(double base, double exp) => math.pow(base, exp).toDouble();
}
