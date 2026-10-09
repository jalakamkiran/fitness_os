import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/program_planner.dart';
import 'package:fitness_os/features/programs/domain/rules_pack/formulas.dart';
import 'package:fitness_os/features/programs/domain/rules_pack/rules_pack.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime(2026, 10, 12); // Monday

Baseline _baseline({
  int capacityM = 1000,
  double? cssPaceSecPer100,
}) {
  return Baseline(
    capacityDistanceM: capacityM,
    cssPaceSecPer100: cssPaceSecPer100,
    confidence: BaselineConfidence.medium,
    reason: BaselineReason.richHistory,
  );
}

ProgramIntake _intake({
  int goalM = 1200,
  int? targetTimeSec,
  int horizonWeeks = 3,
  int sessionsPerWeek = 3,
}) {
  return ProgramIntake(
    goalDistanceM: goalM,
    targetTimeSec: targetTimeSec,
    horizonWeeks: horizonWeeks,
    sessionsPerWeek: sessionsPerWeek,
    poolOnlyAcknowledged: true,
  );
}

/// Week index (0-based) from program start for a YYYY-MM-DD chore day.
int _weekIndex(String dayIso, DateTime start) {
  final parts = dayIso.split('-');
  final d = DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  final startDay = DateTime(start.year, start.month, start.day);
  return d.difference(startDay).inDays ~/ 7;
}

Map<int, int> _weeklyVolumes(Program program, DateTime start) {
  final totals = <int, int>{};
  for (final c in program.chores) {
    if (c.role == ChoreRole.proof) continue;
    final w = _weekIndex(c.dayIso, start);
    totals[w] = (totals[w] ?? 0) + c.targetDistanceM;
  }
  return totals;
}

void main() {
  final planner = ProgramPlanner();

  group('ProgramPlanner.plan dogfood', () {
    test('1000→1200 / 3 wk / 3×: proof week 2–3, three roles, WU/main/CD', () {
      final program = planner.plan(
        intake: _intake(),
        baseline: _baseline(),
        startDate: _start,
        id: 'dogfood',
      );

      expect(program.rulesPackVersion, rulesPackVersion);
      expect(program.poolOnly, isTrue);
      expect(program.milestones, isNotEmpty);
      expect(program.milestones.first.targetDistanceM, 1200);

      final proof = program.milestones.first;
      final proofWeek = _weekIndex(proof.forecastDateIso, _start);
      expect(proofWeek, anyOf(1, 2)); // week 2–3 (0-based 1–2)

      final roles = program.chores.map((c) => c.role).toSet();
      expect(roles, contains(ChoreRole.endurance));
      expect(roles, contains(ChoreRole.quality));
      expect(roles, contains(ChoreRole.technique));
      expect(roles, contains(ChoreRole.proof));

      for (final c in program.chores) {
        expect(c.hasWuMainCd, isTrue, reason: '${c.id} missing WU/main/CD');
      }
    });

    test('sessions/week=2 → endurance + quality only (no technique)', () {
      final program = planner.plan(
        intake: _intake(sessionsPerWeek: 2),
        baseline: _baseline(),
        startDate: _start,
        id: 'two_x',
      );

      final weeklyRoles = program.chores
          .where((c) => c.role != ChoreRole.proof)
          .map((c) => c.role)
          .toSet();
      expect(weeklyRoles, equals({ChoreRole.endurance, ChoreRole.quality}));
      expect(weeklyRoles.contains(ChoreRole.technique), isFalse);
      expect(weeklyRoles.contains(ChoreRole.recovery), isFalse);
    });

    test('aggressive pace vs short horizon → feasibilityWarning set', () {
      // 1200 m in 18:00 → 90 s/100; CSS 115 → large gap vs 3-week horizon.
      final program = planner.plan(
        intake: _intake(targetTimeSec: 18 * 60, horizonWeeks: 3),
        baseline: _baseline(cssPaceSecPer100: 115),
        startDate: _start,
        id: 'pace_gap',
      );

      expect(program.feasibilityWarning, isNotNull);
      expect(program.feasibilityWarning!, contains('time target'));
    });

    test('poolOnly always true on generated program', () {
      final program = planner.plan(
        intake: _intake(),
        baseline: _baseline(),
        startDate: _start,
        id: 'pool',
      );
      expect(program.poolOnly, isTrue);
    });

    test('capacity rung +20% rounds to 50 m (1000→1200)', () {
      expect(
        nextCapacityRung(currentM: 1000, goalM: 1200),
        1200,
      );
    });

    test('900 capacity → 1250 goal: early session scaled, main not continuous ask',
        () {
      final program = planner.plan(
        intake: _intake(goalM: 1250, horizonWeeks: 3),
        baseline: _baseline(capacityM: 900),
        startDate: _start,
        id: 'cap_scale',
      );

      final first = program.chores.firstWhere(
        (c) => c.role == ChoreRole.endurance,
      );
      // Must not jump to the old hard 1500 m / 1300 floor for thin capacity.
      expect(first.targetDistanceM, lessThanOrEqualTo(1300));
      expect(first.targetDistanceM, greaterThanOrEqualTo(1000));
      final main = first.blocks.firstWhere((b) => b.part == 'main');
      expect(main.distanceM, lessThanOrEqualTo(900));
      expect(main.label.toLowerCase(), contains('rest'));
      expect(first.focusLine!.toLowerCase(), contains('broken'));
    });
  });

  group('ProgramPlanner.applyProofOutcome', () {
    test('fail → dates move; weekly volume bump ≤10%', () {
      final program = planner.plan(
        intake: _intake(),
        baseline: _baseline(),
        startDate: _start,
        id: 'fail_slip',
      );
      final ms = program.milestones.first;
      final before = DateTime.parse(ms.forecastDateIso);

      final after = planner.applyProofOutcome(
        program,
        milestoneId: ms.id,
        outcome: ProofOutcome.fail,
        asOf: _start.add(const Duration(days: 14)),
      );

      final afterMs = after.milestones.first;
      final afterDate = DateTime.parse(afterMs.forecastDateIso);
      expect(afterDate.isAfter(before), isTrue);
      expect(
        afterDate.difference(before).inDays,
        failSlipDays,
      );
      expect(after.goalForecastLikelyIso, isNotNull);

      final volumes = _weeklyVolumes(after, _start);
      final weeks = volumes.keys.toList()..sort();
      for (var i = 1; i < weeks.length; i++) {
        final prev = volumes[weeks[i - 1]]!;
        final curr = volumes[weeks[i]]!;
        if (prev <= 0) continue;
        final bump = (curr - prev) / prev;
        expect(
          bump,
          lessThanOrEqualTo(weeklyVolumeGrowthMax + 0.001),
          reason: 'week ${weeks[i - 1]}→${weeks[i]} bump $bump',
        );
      }
    });

    test('nearPass → slip ~7 days, keep rung distance', () {
      final program = planner.plan(
        intake: _intake(),
        baseline: _baseline(),
        startDate: _start,
        id: 'near',
      );
      final ms = program.milestones.first;
      final beforeDist = ms.targetDistanceM;
      final before = DateTime.parse(ms.forecastDateIso);

      final after = planner.applyProofOutcome(
        program,
        milestoneId: ms.id,
        outcome: ProofOutcome.nearPass,
        asOf: _start.add(const Duration(days: 14)),
      );

      expect(after.milestones.first.targetDistanceM, beforeDist);
      expect(
        DateTime.parse(after.milestones.first.forecastDateIso)
            .difference(before)
            .inDays,
        nearPassSlipDays,
      );
    });

    test('pass → milestone marked passed', () {
      final program = planner.plan(
        intake: _intake(),
        baseline: _baseline(),
        startDate: _start,
        id: 'pass',
      );
      final ms = program.milestones.first;
      final after = planner.applyProofOutcome(
        program,
        milestoneId: ms.id,
        outcome: ProofOutcome.pass,
        asOf: _start.add(const Duration(days: 14)),
      );
      expect(after.milestones.first.status.name, 'passed');
      expect(after.milestones.first.passedAtIso, isNotNull);
    });

    test('fail rebuild preserves doneSynced chore history', () {
      final program = planner.plan(
        intake: _intake(),
        baseline: _baseline(),
        startDate: _start,
        id: 'fail_keep',
      );
      final first = program.chores.first;
      final locked = first.copyWith(
        state: ChoreState.doneSynced,
        judgedDistanceM: first.targetDistanceM,
        matchedWorkoutNumber: 7,
        matchedStartTime: 1700000000,
      );
      final withHistory = program.copyWith(
        chores: [locked, ...program.chores.skip(1)],
      );
      final ms = withHistory.milestones.first;

      final after = planner.applyProofOutcome(
        withHistory,
        milestoneId: ms.id,
        outcome: ProofOutcome.fail,
        asOf: _start.add(const Duration(days: 14)),
      );

      final kept = after.chores.where((c) => c.id == locked.id).toList();
      expect(kept, hasLength(1));
      expect(kept.first.state, ChoreState.doneSynced);
      expect(kept.first.dayIso, locked.dayIso);
      expect(kept.first.matchedWorkoutNumber, 7);
    });

    test('nearPass does not move completed chore days', () {
      final program = planner.plan(
        intake: _intake(),
        baseline: _baseline(),
        startDate: _start,
        id: 'near_keep',
      );
      final first = program.chores.first;
      final locked = first.copyWith(state: ChoreState.doneManual);
      final withHistory = program.copyWith(
        chores: [locked, ...program.chores.skip(1)],
      );
      final ms = withHistory.milestones.first;
      final beforeDay = locked.dayIso;

      final after = planner.applyProofOutcome(
        withHistory,
        milestoneId: ms.id,
        outcome: ProofOutcome.nearPass,
        asOf: _start.add(const Duration(days: 14)),
      );

      final kept = after.chores.firstWhere((c) => c.id == locked.id);
      expect(kept.dayIso, beforeDay);
      expect(kept.state, ChoreState.doneManual);
    });
  });

  group('rolesForSessionsPerWeek', () {
    test('4–5 add easy/recovery', () {
      expect(
        ProgramPlanner.rolesForSessionsPerWeek(4),
        contains(ChoreRole.easy),
      );
      expect(
        ProgramPlanner.rolesForSessionsPerWeek(5),
        containsAll([ChoreRole.easy, ChoreRole.recovery]),
      );
    });
  });
}
