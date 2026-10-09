import 'package:fitness_os/features/programs/domain/chore_matcher.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/program_planner.dart';
import 'package:fitness_os/features/workout_history/domain/in_session_hr_lock.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed local noon for deterministic Unix seconds.
final _asOf = DateTime(2026, 10, 9, 12);

int _unixSec(DateTime local) => local.millisecondsSinceEpoch ~/ 1000;

PoolSwimCandidate _pool({
  required int n,
  required DateTime start,
  required int distanceM,
  int durationSec = 2400,
  int type = poolSwimWorkoutType,
}) {
  return PoolSwimCandidate(
    workoutNumber: n,
    startTime: _unixSec(start),
    type: type,
    distanceM: distanceM,
    durationSec: durationSec,
  );
}

ChoreSession _chore({
  required String id,
  required String dayIso,
  required int targetDistanceM,
  ChoreRole role = ChoreRole.endurance,
  ChoreState state = ChoreState.due,
  int? mainDistanceM,
  String? milestoneId,
}) {
  final main = mainDistanceM ?? (targetDistanceM * 2 ~/ 3);
  return ChoreSession(
    id: id,
    programId: 'prog_1',
    dayIso: dayIso,
    role: role,
    state: state,
    blocks: [
      ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 200),
      ChoreBlock(part: 'main', label: 'Main', distanceM: main),
      ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 200),
    ],
    targetDistanceM: targetDistanceM,
    milestoneId: milestoneId,
  );
}

Program _program(List<ChoreSession> chores, {List<Milestone>? milestones}) {
  return Program(
    id: 'prog_1',
    intake: const ProgramIntake(
      goalDistanceM: 1200,
      horizonWeeks: 3,
      sessionsPerWeek: 3,
      poolOnlyAcknowledged: true,
    ),
    status: ProgramStatus.active,
    createdAtMs: _asOf.millisecondsSinceEpoch,
    rulesPackVersion: 'test',
    schemaVersion: Program.currentSchemaVersion,
    milestones: milestones ?? const [],
    chores: chores,
  );
}

Milestone _milestone({
  String id = 'ms_0',
  int targetDistanceM = 1200,
}) {
  return Milestone(
    id: id,
    index: 0,
    targetDistanceM: targetDistanceM,
    plannedDateIso: '2026-10-09',
    forecastDateIso: '2026-10-09',
    status: MilestoneStatus.due,
  );
}

void main() {
  final matcher = ChoreMatcher();

  group('ChoreMatcher.matchChores', () {
    test('happy: synced pool swim matches today’s endurance chore → doneSynced',
        () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-09',
        targetDistanceM: 1400,
        state: ChoreState.due,
      );
      final swim = _pool(
        n: 42,
        start: DateTime(2026, 10, 9, 7, 30),
        distanceM: 1400,
        durationSec: 2800,
      );

      final results = matcher.matchChores(
        program: _program([chore]),
        swims: [swim],
        asOf: _asOf,
      );

      expect(results, hasLength(1));
      final matched = results.single.chore;
      expect(matched.state, ChoreState.doneSynced);
      expect(matched.matchedWorkoutNumber, 42);
      expect(matched.matchedStartTime, swim.startTime);
      expect(matched.judgedDistanceM, 1400);
      expect(matched.judgedDurationSec, 2800);
      expect(matched.completedAtMs, _asOf.millisecondsSinceEpoch);
    });

    test('OW (type 8) swim never matches pool chore', () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-09',
        targetDistanceM: 1400,
      );
      final ow = _pool(
        n: 99,
        start: DateTime(2026, 10, 9, 8),
        distanceM: 1400,
        type: openWaterSwimWorkoutType,
      );

      final results = matcher.matchChores(
        program: _program([chore]),
        swims: [ow],
        asOf: _asOf,
      );

      expect(results, isEmpty);
    });

    test('distance outside ±5% does not match', () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-09',
        targetDistanceM: 1400,
      );
      // 10% over target
      final swim = _pool(
        n: 1,
        start: DateTime(2026, 10, 9, 8),
        distanceM: 1540,
      );

      expect(
        matcher.matchChores(
          program: _program([chore]),
          swims: [swim],
          asOf: _asOf,
        ),
        isEmpty,
      );
    });

    test('main-block distance within tolerance matches', () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-09',
        targetDistanceM: 1600,
        mainDistanceM: 1000,
      );
      final swim = _pool(
        n: 7,
        start: DateTime(2026, 10, 9, 9),
        distanceM: 1000, // matches main, not total
      );

      final results = matcher.matchChores(
        program: _program([chore]),
        swims: [swim],
        asOf: _asOf,
      );

      expect(results, hasLength(1));
      expect(results.single.chore.state, ChoreState.doneSynced);
    });

    test('lapsed chore rematches within 72 h late-sync window', () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-07',
        targetDistanceM: 1200,
        state: ChoreState.lapsed,
      );
      final swim = _pool(
        n: 3,
        start: DateTime(2026, 10, 7, 18),
        distanceM: 1200,
      );
      // 48 h after chore day start — still inside 72 h
      final asOf = DateTime(2026, 10, 9, 10);

      final results = matcher.matchChores(
        program: _program([chore]),
        swims: [swim],
        asOf: asOf,
      );

      expect(results, hasLength(1));
      expect(results.single.chore.state, ChoreState.doneSynced);
    });

    test('lapsed chore does not rematch after late-sync window', () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-05',
        targetDistanceM: 1200,
        state: ChoreState.lapsed,
      );
      final swim = _pool(
        n: 3,
        start: DateTime(2026, 10, 5, 18),
        distanceM: 1200,
      );
      // >72 h after chore day
      final asOf = DateTime(2026, 10, 9, 12);

      expect(
        matcher.matchChores(
          program: _program([chore]),
          swims: [swim],
          asOf: asOf,
        ),
        isEmpty,
      );
    });

    test('already-done chore is not rematched', () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-09',
        targetDistanceM: 1400,
        state: ChoreState.doneManual,
      );
      final swim = _pool(
        n: 1,
        start: DateTime(2026, 10, 9, 8),
        distanceM: 1400,
      );

      expect(
        matcher.matchChores(
          program: _program([chore]),
          swims: [swim],
          asOf: _asOf,
        ),
        isEmpty,
      );
    });
  });

  group('ChoreMatcher.matchProof', () {
    test('AE5: proof fail → matcher returns fail (no planner slip here)', () {
      final ms = _milestone(targetDistanceM: 1200);
      final swim = _pool(
        n: 10,
        start: DateTime(2026, 10, 9, 7),
        distanceM: 800, // well under 90%
      );

      final result = matcher.matchProof(
        milestone: ms,
        swim: swim,
        continuousConfirmed: true,
      );

      expect(result.outcome, ProofOutcome.fail);
      expect(result.judgedDistanceM, 800);
      // Matcher does not invoke ProgramPlanner — outcome only.
    });

    test('pass when distance ≥ target and continuous confirmed', () {
      final result = matcher.matchProof(
        milestone: _milestone(targetDistanceM: 1200),
        swim: _pool(
          n: 1,
          start: DateTime(2026, 10, 9, 7),
          distanceM: 1200,
        ),
        continuousConfirmed: true,
      );

      expect(result.outcome, ProofOutcome.pass);
    });

    test('nearPass when distance ≥ 90% but under target', () {
      final result = matcher.matchProof(
        milestone: _milestone(targetDistanceM: 1200),
        swim: _pool(
          n: 1,
          start: DateTime(2026, 10, 9, 7),
          distanceM: 1080, // exactly 90%
        ),
        continuousConfirmed: true,
      );

      expect(result.outcome, ProofOutcome.nearPass);
    });

    test('manual continuous confirm → pass without wire continuity', () {
      // v1: continuity not computable; athlete confirm unlocks pass.
      final result = matcher.matchProof(
        milestone: _milestone(targetDistanceM: 1200),
        swim: _pool(
          n: 5,
          start: DateTime(2026, 10, 9, 7),
          distanceM: 1250,
        ),
        continuousConfirmed: true,
      );

      expect(result.outcome, ProofOutcome.pass);
      expect(result.continuousConfirmed, isTrue);
    });

    test('without continuousConfirmed, distance-ok proof still fails', () {
      final result = matcher.matchProof(
        milestone: _milestone(targetDistanceM: 1200),
        swim: _pool(
          n: 5,
          start: DateTime(2026, 10, 9, 7),
          distanceM: 1250,
        ),
        continuousConfirmed: false,
      );

      expect(result.outcome, ProofOutcome.fail);
    });

    test('OW swim proof always fails', () {
      final result = matcher.matchProof(
        milestone: _milestone(targetDistanceM: 1200),
        swim: _pool(
          n: 8,
          start: DateTime(2026, 10, 9, 7),
          distanceM: 1200,
          type: openWaterSwimWorkoutType,
        ),
        continuousConfirmed: true,
      );

      expect(result.outcome, ProofOutcome.fail);
    });
  });

  group('ChoreMatcher.applyManual', () {
    test('skip excused / other updates chore only — no proof outcome', () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-09',
        targetDistanceM: 1400,
        role: ChoreRole.proof,
        milestoneId: 'ms_0',
      );

      final excused = matcher.applyManual(
        chore: chore,
        action: ManualChoreAction.skippedExcused,
        skipReason: SkipReason.otherLoad,
        asOf: _asOf,
      );
      expect(excused.state, ChoreState.skippedExcused);
      expect(excused.skipReason, SkipReason.otherLoad);
      expect(excused.milestoneId, 'ms_0'); // unchanged; no slip event

      final other = matcher.applyManual(
        chore: chore,
        action: ManualChoreAction.skippedOther,
        skipReason: SkipReason.ill,
        asOf: _asOf,
      );
      expect(other.state, ChoreState.skippedOther);
      expect(other.skipReason, SkipReason.ill);
    });

    test('doneManual and adjusted set completedAtMs', () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-09',
        targetDistanceM: 1400,
      );

      final done = matcher.applyManual(
        chore: chore,
        action: ManualChoreAction.doneManual,
        asOf: _asOf,
      );
      expect(done.state, ChoreState.doneManual);
      expect(done.completedAtMs, _asOf.millisecondsSinceEpoch);

      final adjusted = matcher.applyManual(
        chore: chore,
        action: ManualChoreAction.adjusted,
        asOf: _asOf,
      );
      expect(adjusted.state, ChoreState.adjusted);
    });

    test('moved updates state without proof outcome', () {
      final chore = _chore(
        id: 'c1',
        dayIso: '2026-10-09',
        targetDistanceM: 1400,
        milestoneId: 'ms_0',
      );

      final moved = matcher.applyManual(
        chore: chore,
        action: ManualChoreAction.moved,
        asOf: _asOf,
      );
      expect(moved.state, ChoreState.moved);
      expect(moved.milestoneId, 'ms_0');
    });
  });
}
