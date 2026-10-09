import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';

/// Habit-band labels (words only — never grades or proof gates).
enum HabitBand {
  light,
  building,
  steady,
}

/// Efficiency data status: honest "Collecting" until enough matched-pace data.
enum EfficiencyStatus {
  collecting,
  ready,
}

/// One matched-pace efficiency sample (session-level).
class EfficiencySample {
  const EfficiencySample({
    required this.sessionId,
    required this.dpsM,
    this.paceFade,
    this.swolf,
    this.matchedPace = true,
  });

  final String sessionId;

  /// Distance per stroke (metres) at matched pace.
  final double dpsM;

  /// Last-third pace ÷ first-third pace (≥1.0 means fade / slowing).
  final double? paceFade;

  /// Secondary SWOLF at matched pace (pool-normalized by caller).
  final double? swolf;

  /// When false, sample is ignored for primary DPS/fade.
  final bool matchedPace;
}

/// Habit scorecard: showing up vs plan (excused removed from denominator).
class HabitScorecard {
  const HabitScorecard({
    required this.numerator,
    required this.denominator,
    required this.ratio,
    required this.band,
    required this.doneSynced,
    required this.doneManual,
    required this.adjusted,
    required this.excused,
    required this.prescribed,
    required this.focusLine,
    this.weeksAtFloor = 0,
    this.restPassesLeft = 0,
  });

  final double numerator;
  final int denominator;
  final double ratio;
  final HabitBand band;
  final int doneSynced;
  final int doneManual;
  final int adjusted;
  final int excused;
  final int prescribed;
  final String focusLine;
  final int weeksAtFloor;
  final int restPassesLeft;

  /// Display fraction text, e.g. `4 of 6 sessions`.
  String get displayFraction {
    final done = doneSynced + doneManual + adjusted;
    return '$done of $denominator sessions';
  }
}

/// Volume scorecard: longest continuous vs next proof + weekly distance.
class VolumeScorecard {
  const VolumeScorecard({
    required this.longestContinuousM,
    required this.nextProofDistanceM,
    required this.capacityGapM,
    required this.weeklyDistanceM,
    required this.plannedWeeklyDistanceM,
    required this.planRatio,
    required this.focusLine,
    this.ramp,
  });

  final int longestContinuousM;
  final int nextProofDistanceM;

  /// `proof − capacity` (0 when at/above proof).
  final int capacityGapM;
  final int weeklyDistanceM;
  final int plannedWeeklyDistanceM;
  final double planRatio;
  final String focusLine;

  /// `weekly / mean(previous 3 weeks)` when known.
  final double? ramp;
}

/// Efficiency scorecard: matched-pace DPS + pace fade; SWOLF secondary.
class EfficiencyScorecard {
  const EfficiencyScorecard({
    required this.status,
    required this.focusLine,
    this.medianDpsM,
    this.dpsDeltaVsBaseline,
    this.medianPaceFade,
    this.medianSwolf,
    this.qualifyingSessionCount = 0,
  });

  final EfficiencyStatus status;
  final String focusLine;
  final double? medianDpsM;
  final double? dpsDeltaVsBaseline;
  final double? medianPaceFade;
  final double? medianSwolf;
  final int qualifyingSessionCount;

  bool get isCollecting => status == EfficiencyStatus.collecting;
}

/// Bundle of three independent cards — never a composite, never gates proofs.
class ScorecardBundle {
  const ScorecardBundle({
    required this.habit,
    required this.volume,
    required this.efficiency,
    required this.focusLine,
    this.blockProof = false,
  });

  final HabitScorecard habit;
  final VolumeScorecard volume;
  final EfficiencyScorecard efficiency;

  /// Single deterministic line for the next chore header.
  final String focusLine;

  /// Always false in v1 (R16). Kept so callers cannot invent a gate.
  final bool blockProof;
}

/// Deterministic Habit / Volume / Efficiency scorecards (gamification §5–6).
abstract final class Scorecards {
  static const int minEfficiencySessions = 3;
  static const double adjustedWeight = 0.6;

  static ScorecardBundle compute({
    required Program program,
    required ProgressLedger ledger,
    int? longestContinuousM,
    List<EfficiencySample>? efficiencySamples,
    int? weeklyDistanceM,
    List<int>? priorWeeklyDistancesM,
    double? baselineDpsM,
  }) {
    final habit = _habit(program, ledger);
    final volume = _volume(
      program,
      longestContinuousM: longestContinuousM,
      weeklyDistanceM: weeklyDistanceM,
      priorWeeklyDistancesM: priorWeeklyDistancesM,
    );
    final efficiency = _efficiency(
      samples: efficiencySamples ?? const [],
      baselineDpsM: baselineDpsM,
    );

    final focus = _pickFocus(habit, volume, efficiency);
    return ScorecardBundle(
      habit: habit,
      volume: volume,
      efficiency: efficiency,
      focusLine: focus,
      blockProof: false,
    );
  }

  static HabitScorecard _habit(Program program, ProgressLedger ledger) {
    var doneSynced = 0;
    var doneManual = 0;
    var adjusted = 0;
    var excused = 0;
    final seen = <String>{};

    // Prefer live program chore states; fall back to ledger events.
    final chores = program.chores;
    if (chores.isNotEmpty) {
      for (final c in chores) {
        if (c.state == ChoreState.superseded) continue;
        switch (c.state) {
          case ChoreState.doneSynced:
            doneSynced++;
            break;
          case ChoreState.doneManual:
            doneManual++;
            break;
          case ChoreState.adjusted:
            adjusted++;
            break;
          case ChoreState.skippedExcused:
            excused++;
            break;
          case ChoreState.scheduled:
          case ChoreState.due:
          case ChoreState.moved:
          case ChoreState.skippedOther:
          case ChoreState.lapsed:
          case ChoreState.superseded:
            break;
        }
      }
    } else {
      for (final e in ledger.choreEvents) {
        if (!seen.add(e.choreId)) continue;
        if (e.state == ChoreState.doneSynced.name) {
          doneSynced++;
        } else if (e.state == ChoreState.doneManual.name) {
          doneManual++;
        } else if (e.state == ChoreState.adjusted.name) {
          adjusted++;
        } else if (e.state == ChoreState.skippedExcused.name) {
          excused++;
        }
      }
    }

    final prescribed = chores.isNotEmpty
        ? chores.where((c) => c.state != ChoreState.superseded).length
        : _prescribedFromLedger(ledger, program);
    final denominator = (prescribed - excused).clamp(0, 100000);
    final numerator =
        doneSynced + doneManual + adjustedWeight * adjusted;
    final ratio = denominator == 0 ? 0.0 : numerator / denominator;

    final HabitBand band;
    if (ratio >= 0.85) {
      band = HabitBand.steady;
    } else if (ratio >= 0.6) {
      band = HabitBand.building;
    } else {
      band = HabitBand.light;
    }

    final focus = band == HabitBand.light
        ? 'Focus: swim the next planned session'
        : band == HabitBand.building
            ? 'Focus: keep the weekly floor'
            : 'Focus: hold the habit';

    return HabitScorecard(
      numerator: numerator,
      denominator: denominator,
      ratio: ratio,
      band: band,
      doneSynced: doneSynced,
      doneManual: doneManual,
      adjusted: adjusted,
      excused: excused,
      prescribed: prescribed,
      focusLine: focus,
      weeksAtFloor: ledger.currentStreakWeeks,
      restPassesLeft: ledger.restPasses,
    );
  }

  static int _prescribedFromLedger(ProgressLedger ledger, Program program) {
    final ids = ledger.choreEvents.map((e) => e.choreId).toSet();
    if (ids.isNotEmpty) return ids.length;
    return program.intake.sessionsPerWeek;
  }

  static VolumeScorecard _volume(
    Program program, {
    int? longestContinuousM,
    int? weeklyDistanceM,
    List<int>? priorWeeklyDistancesM,
  }) {
    final capacity = longestContinuousM ??
        program.baseline?.capacityDistanceM ??
        0;
    final nextProof = _nextProofDistanceM(program);
    final gap = (nextProof - capacity).clamp(0, 1000000);
    final weekly = weeklyDistanceM ??
        program.chores
            .where(
              (c) =>
                  c.state == ChoreState.doneSynced ||
                  c.state == ChoreState.doneManual ||
                  c.state == ChoreState.adjusted,
            )
            .fold<int>(0, (s, c) => s + (c.judgedDistanceM ?? c.targetDistanceM));
    final planned = program.chores
        .where((c) => c.state != ChoreState.superseded)
        .fold<int>(0, (s, c) => s + c.targetDistanceM);
    final planRatio = planned <= 0 ? 0.0 : weekly / planned;

    double? ramp;
    final priors = priorWeeklyDistancesM ?? const <int>[];
    if (priors.length >= 3) {
      final mean = priors
              .sublist(priors.length - 3)
              .fold<int>(0, (a, b) => a + b) /
          3.0;
      if (mean > 0) ramp = weekly / mean;
    }

    final focus = gap > 0
        ? 'Focus: build the long swim'
        : 'Focus: hold continuous capacity';

    return VolumeScorecard(
      longestContinuousM: capacity,
      nextProofDistanceM: nextProof,
      capacityGapM: gap,
      weeklyDistanceM: weekly,
      plannedWeeklyDistanceM: planned,
      planRatio: planRatio,
      focusLine: focus,
      ramp: ramp,
    );
  }

  static int _nextProofDistanceM(Program program) {
    for (final m in program.milestones) {
      switch (m.status) {
        case MilestoneStatus.upcoming:
        case MilestoneStatus.due:
        case MilestoneStatus.failed:
        case MilestoneStatus.delayed:
        case MilestoneStatus.nearPass:
          return m.targetDistanceM;
        case MilestoneStatus.passed:
        case MilestoneStatus.paused:
        case MilestoneStatus.superseded:
          break;
      }
    }
    return program.intake.goalDistanceM;
  }

  static EfficiencyScorecard _efficiency({
    required List<EfficiencySample> samples,
    double? baselineDpsM,
  }) {
    final matched =
        samples.where((s) => s.matchedPace && s.dpsM > 0).toList();
    if (matched.length < minEfficiencySessions) {
      return EfficiencyScorecard(
        status: EfficiencyStatus.collecting,
        focusLine: 'Focus: keep collecting pace data',
        qualifyingSessionCount: matched.length,
      );
    }

    final dpsValues = matched.map((s) => s.dpsM).toList()..sort();
    final medianDps = _median(dpsValues);
    final fades = matched
        .map((s) => s.paceFade)
        .whereType<double>()
        .toList()
      ..sort();
    final medianFade = fades.isEmpty ? null : _median(fades);
    final swolfs = matched
        .map((s) => s.swolf)
        .whereType<double>()
        .toList()
      ..sort();
    final medianSwolf = swolfs.isEmpty ? null : _median(swolfs);

    double? delta;
    if (baselineDpsM != null && baselineDpsM > 0) {
      delta = medianDps - baselineDpsM;
    }

    final fadeHigh = medianFade != null && medianFade >= 1.05;
    final focus = fadeHigh
        ? 'Focus: even splits'
        : 'Focus: hold matched-pace stroke length';

    return EfficiencyScorecard(
      status: EfficiencyStatus.ready,
      focusLine: focus,
      medianDpsM: medianDps,
      dpsDeltaVsBaseline: delta,
      medianPaceFade: medianFade,
      medianSwolf: medianSwolf,
      qualifyingSessionCount: matched.length,
    );
  }

  static double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// One focus line: prefer Efficiency fade, then Volume gap, then Habit.
  static String _pickFocus(
    HabitScorecard habit,
    VolumeScorecard volume,
    EfficiencyScorecard efficiency,
  ) {
    if (efficiency.status == EfficiencyStatus.ready &&
        efficiency.medianPaceFade != null &&
        efficiency.medianPaceFade! >= 1.05) {
      return efficiency.focusLine;
    }
    if (volume.capacityGapM > 0) return volume.focusLine;
    if (habit.band == HabitBand.light) return habit.focusLine;
    if (efficiency.status == EfficiencyStatus.collecting) {
      return efficiency.focusLine;
    }
    return habit.focusLine;
  }
}
