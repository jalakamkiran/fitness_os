import 'dart:io';

import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Program _program({
  required String todayIso,
  required String nextIso,
  required ChoreState todayState,
}) {
  return Program(
    id: 'p-advance',
    intake: const ProgramIntake(
      goalDistanceM: 1200,
      horizonWeeks: 3,
      sessionsPerWeek: 2,
      poolOnlyAcknowledged: true,
    ),
    status: ProgramStatus.active,
    createdAtMs: 1,
    activatedAtMs: 1,
    rulesPackVersion: '1.0.0',
    schemaVersion: Program.currentSchemaVersion,
    baseline: const Baseline(
      capacityDistanceM: 900,
      confidence: BaselineConfidence.medium,
      reason: BaselineReason.richHistory,
    ),
    milestones: [
      Milestone(
        id: 'm1',
        index: 0,
        targetDistanceM: 1200,
        plannedDateIso: '2026-11-05',
        forecastDateIso: '2026-11-05',
        status: MilestoneStatus.upcoming,
      ),
    ],
    chores: [
      ChoreSession(
        id: 'c-today',
        programId: 'p-advance',
        dayIso: todayIso,
        role: ChoreRole.endurance,
        state: todayState,
        targetDistanceM: 1200,
        focusLine: 'Long steady',
        blocks: const [
          ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 300),
          ChoreBlock(part: 'main', label: 'Main', distanceM: 800),
          ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 100),
        ],
      ),
      ChoreSession(
        id: 'c-next',
        programId: 'p-advance',
        dayIso: nextIso,
        role: ChoreRole.endurance,
        state: ChoreState.scheduled,
        targetDistanceM: 1000,
        focusLine: 'Next course',
        blocks: const [
          ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 200),
          ChoreBlock(part: 'main', label: 'Main', distanceM: 600),
          ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 200),
        ],
      ),
    ],
    poolOnly: true,
  );
}

void main() {
  test('todaysChore advances to next open after today is done', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final root = await Directory.systemTemp.createTemp('todays_chore_');
    addTearDown(() async {
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } catch (_) {}
    });

    final now = DateTime(2026, 10, 9);
    final store = ProgramStore(prefs: prefs, rootOverride: () => root);
    await store.activate(
      _program(
        todayIso: '2026-10-09',
        nextIso: '2026-10-11',
        todayState: ChoreState.doneSynced,
      ),
    );

    final controller = ProgramsController(
      store: store,
      prefs: prefs,
      now: () => now,
    );
    await controller.load();

    expect(controller.todaysChore?.id, 'c-next');
    expect(controller.todaysChoreIncludingDone?.id, 'c-today');
    expect(controller.trialNeedsManualRecord, isFalse);
  });

  test('todaysChore keeps open today session', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final root = await Directory.systemTemp.createTemp('todays_chore_open_');
    addTearDown(() async {
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } catch (_) {}
    });

    final now = DateTime(2026, 10, 9);
    final store = ProgramStore(prefs: prefs, rootOverride: () => root);
    await store.activate(
      _program(
        todayIso: '2026-10-09',
        nextIso: '2026-10-11',
        todayState: ChoreState.scheduled,
      ),
    );

    final controller = ProgramsController(
      store: store,
      prefs: prefs,
      now: () => now,
    );
    await controller.load();

    expect(controller.todaysChore?.id, 'c-today');
  });
}
