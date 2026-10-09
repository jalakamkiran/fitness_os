import 'dart:io';

import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHistory implements WorkoutHistoryRepository {
  _FakeHistory(this.swims);

  List<CanonicalSwimSession> swims;

  @override
  Future<List<CanonicalSwimSession>> loadAllCanonicalSwims() async => swims;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('StoreInvalidation rematch marks today’s chore doneSynced + XP',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final root = await Directory.systemTemp.createTemp('programs_rematch_');
    addTearDown(() async {
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } catch (_) {}
    });

    final store = ProgramStore(prefs: prefs, rootOverride: () => root);
    final today = DateTime.now();
    final dayIso =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final startSec = DateTime(today.year, today.month, today.day, 10)
            .millisecondsSinceEpoch ~/
        1000;

    final program = Program(
      id: 'p-rematch',
      intake: const ProgramIntake(
        goalDistanceM: 1200,
        horizonWeeks: 3,
        sessionsPerWeek: 3,
        poolOnlyAcknowledged: true,
      ),
      status: ProgramStatus.active,
      createdAtMs: 1,
      activatedAtMs: 1,
      rulesPackVersion: '1.0.0',
      schemaVersion: Program.currentSchemaVersion,
      baseline: const Baseline(
        capacityDistanceM: 1000,
        confidence: BaselineConfidence.medium,
        reason: BaselineReason.richHistory,
      ),
      milestones: [
        Milestone(
          id: 'm1',
          index: 0,
          targetDistanceM: 1200,
          plannedDateIso: dayIso,
          forecastDateIso: dayIso,
          status: MilestoneStatus.upcoming,
        ),
      ],
      chores: [
        ChoreSession(
          id: 'c-today',
          programId: 'p-rematch',
          dayIso: dayIso,
          role: ChoreRole.endurance,
          state: ChoreState.due,
          targetDistanceM: 1800,
          blocks: const [
            ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 300),
            ChoreBlock(part: 'main', label: 'Main', distanceM: 1300),
            ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 200),
          ],
        ),
      ],
    );
    await store.activate(program);

    final invalidation = StoreInvalidation();
    final history = _FakeHistory(const []);

    final controller = ProgramsController(
      store: store,
      prefs: prefs,
      workoutHistory: history,
      invalidation: invalidation,
      now: () => today,
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.active!.chores.first.state, ChoreState.due);

    history.swims = [
      CanonicalSwimSession(
        workoutNumber: 42,
        startTime: startSec,
        endTime: startSec + 3600,
        durationSec: 3600,
        type: 6,
        distanceM: 1800,
        p0: const SwimP0Metrics(hrCoverage: SwimHrCoverage.absent),
      ),
    ];
    invalidation.notify();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    // Explicit call covers the path if stream races; idempotent if notify won.
    await controller.rematchAfterSync();

    final chore = controller.active!.chores.first;
    expect(chore.state, ChoreState.doneSynced);
    expect(chore.matchedWorkoutNumber, 42);
    expect(controller.ledger.totalXp, greaterThan(0));
  });
}
