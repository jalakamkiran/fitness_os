import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';
import 'package:fitness_os/features/programs/domain/scorecards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime(2026, 10, 5).millisecondsSinceEpoch;

  ChoreSession chore({
    required String id,
    required ChoreState state,
    int targetDistanceM = 1000,
    int? judgedDistanceM,
    SkipReason? skipReason,
  }) {
    return ChoreSession(
      id: id,
      programId: 'prog_1',
      dayIso: '2026-10-05',
      role: ChoreRole.endurance,
      state: state,
      blocks: [
        const ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 200),
        ChoreBlock(
          part: 'main',
          label: 'Main',
          distanceM: targetDistanceM - 400,
        ),
        const ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 200),
      ],
      targetDistanceM: targetDistanceM,
      judgedDistanceM: judgedDistanceM,
      skipReason: skipReason,
    );
  }

  Program program({
    List<ChoreSession>? chores,
    List<Milestone>? milestones,
    int capacityM = 1000,
  }) {
    return Program(
      id: 'prog_1',
      intake: const ProgramIntake(
        goalDistanceM: 1200,
        horizonWeeks: 3,
        sessionsPerWeek: 3,
        poolOnlyAcknowledged: true,
      ),
      status: ProgramStatus.active,
      createdAtMs: created,
      rulesPackVersion: 'test',
      schemaVersion: Program.currentSchemaVersion,
      baseline: Baseline(
        capacityDistanceM: capacityM,
        confidence: BaselineConfidence.medium,
        reason: BaselineReason.sparseHistory,
      ),
      milestones: milestones ??
          [
            const Milestone(
              id: 'ms_0',
              index: 0,
              targetDistanceM: 1200,
              plannedDateIso: '2026-10-15',
              forecastDateIso: '2026-10-15',
              status: MilestoneStatus.upcoming,
            ),
          ],
      chores: chores ?? const [],
    );
  }

  group('Scorecards.compute', () {
    test('habit: synced + manual + 0.6×adjusted over prescribed − excused', () {
      final prog = program(
        chores: [
          chore(id: 'a', state: ChoreState.doneSynced),
          chore(id: 'b', state: ChoreState.doneManual),
          chore(id: 'c', state: ChoreState.adjusted),
          chore(
            id: 'd',
            state: ChoreState.skippedExcused,
            skipReason: SkipReason.recovery,
          ),
          chore(id: 'e', state: ChoreState.skippedOther),
          chore(id: 'f', state: ChoreState.scheduled),
        ],
      );

      final bundle = Scorecards.compute(
        program: prog,
        ledger: const ProgressLedger(),
      );

      // prescribed 6, excused 1 → denom 5
      // num = 1 + 1 + 0.6 = 2.6 → ratio 0.52
      expect(bundle.habit.prescribed, 6);
      expect(bundle.habit.excused, 1);
      expect(bundle.habit.denominator, 5);
      expect(bundle.habit.numerator, closeTo(2.6, 1e-9));
      expect(bundle.habit.ratio, closeTo(2.6 / 5, 1e-9));
      expect(bundle.habit.band, HabitBand.light);
    });

    test('volume: longest continuous vs next proof + weekly distance', () {
      final prog = program(
        capacityM: 1000,
        chores: [
          chore(
            id: 'a',
            state: ChoreState.doneSynced,
            targetDistanceM: 1200,
            judgedDistanceM: 1200,
          ),
          chore(
            id: 'b',
            state: ChoreState.doneManual,
            targetDistanceM: 1000,
            judgedDistanceM: 1000,
          ),
        ],
      );

      final bundle = Scorecards.compute(
        program: prog,
        ledger: const ProgressLedger(),
        longestContinuousM: 1100,
        weeklyDistanceM: 2200,
      );

      expect(bundle.volume.longestContinuousM, 1100);
      expect(bundle.volume.nextProofDistanceM, 1200);
      expect(bundle.volume.capacityGapM, 100);
      expect(bundle.volume.weeklyDistanceM, 2200);
      expect(bundle.volume.focusLine, contains('long swim'));
    });

    test('efficiency: Collecting until ≥3 matched-pace sessions', () {
      final prog = program();
      final collecting = Scorecards.compute(
        program: prog,
        ledger: const ProgressLedger(),
        efficiencySamples: const [
          EfficiencySample(sessionId: 's1', dpsM: 2.1),
          EfficiencySample(sessionId: 's2', dpsM: 2.0),
        ],
      );
      expect(collecting.efficiency.status, EfficiencyStatus.collecting);
      expect(collecting.efficiency.isCollecting, isTrue);
      expect(collecting.efficiency.medianDpsM, isNull);

      final ready = Scorecards.compute(
        program: prog,
        ledger: const ProgressLedger(),
        efficiencySamples: const [
          EfficiencySample(sessionId: 's1', dpsM: 2.1, paceFade: 1.02),
          EfficiencySample(sessionId: 's2', dpsM: 2.0, paceFade: 1.08),
          EfficiencySample(sessionId: 's3', dpsM: 2.2, paceFade: 1.06),
          EfficiencySample(
            sessionId: 's4',
            dpsM: 3.0,
            matchedPace: false,
          ),
        ],
        baselineDpsM: 2.0,
      );
      expect(ready.efficiency.status, EfficiencyStatus.ready);
      expect(ready.efficiency.qualifyingSessionCount, 3);
      expect(ready.efficiency.medianDpsM, closeTo(2.1, 1e-9));
      expect(ready.efficiency.medianPaceFade, closeTo(1.06, 1e-9));
      expect(ready.efficiency.focusLine, contains('even splits'));
    });

    test('edge: scorecards do not gate proof (blockProof always false)', () {
      final prog = program(
        chores: [
          chore(id: 'a', state: ChoreState.skippedOther),
          chore(id: 'b', state: ChoreState.lapsed),
        ],
      );
      final bundle = Scorecards.compute(
        program: prog,
        ledger: const ProgressLedger(restPasses: 0, currentStreakWeeks: 0),
        longestContinuousM: 200,
        efficiencySamples: const [],
      );

      expect(bundle.blockProof, isFalse);
      // No alternate gate flag on children either.
      expect(bundle.toString(), isNot(contains('blockProof: true')));
    });

    test('AE4 spirit: excused shrinks habit denominator; no proof gate', () {
      final prog = program(
        chores: [
          chore(id: 'a', state: ChoreState.doneSynced),
          chore(
            id: 'b',
            state: ChoreState.skippedExcused,
            skipReason: SkipReason.otherLoad,
          ),
          chore(id: 'c', state: ChoreState.scheduled),
        ],
      );
      final bundle = Scorecards.compute(
        program: prog,
        ledger: const ProgressLedger(),
      );

      expect(bundle.habit.excused, 1);
      expect(bundle.habit.denominator, 2); // 3 prescribed − 1 excused
      expect(bundle.blockProof, isFalse);
    });
  });
}
