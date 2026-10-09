import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/home/presentation/view/home_screen.dart';
import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/domain/baseline.dart' as prog;
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';

Program _activeProgram() {
  final activatedAt = DateTime(2026, 10, 8).millisecondsSinceEpoch;
  return Program(
    id: 'p-home-agon',
    intake: const ProgramIntake(
      goalDistanceM: 1200,
      horizonWeeks: 3,
      sessionsPerWeek: 3,
      poolOnlyAcknowledged: true,
    ),
    status: ProgramStatus.active,
    createdAtMs: activatedAt,
    activatedAtMs: activatedAt,
    rulesPackVersion: '1.0.0',
    schemaVersion: Program.currentSchemaVersion,
    baseline: const prog.Baseline(
      capacityDistanceM: 1000,
      confidence: prog.BaselineConfidence.medium,
      reason: prog.BaselineReason.richHistory,
    ),
    milestones: const [
      Milestone(
        id: 'm1',
        index: 0,
        targetDistanceM: 1200,
        plannedDateIso: '2026-10-20',
        forecastDateIso: '2026-10-20',
        status: MilestoneStatus.upcoming,
      ),
    ],
    chores: const [
      ChoreSession(
        id: 'c1',
        programId: 'p-home-agon',
        dayIso: '2026-10-09',
        role: ChoreRole.endurance,
        state: ChoreState.scheduled,
        targetDistanceM: 900,
        focusLine: 'Steady',
        blocks: [
          ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 200),
          ChoreBlock(part: 'main', label: 'Main', distanceM: 500),
          ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 200),
        ],
      ),
    ],
    goalForecastLikelyIso: '2026-10-31',
    goalForecastEarliestIso: '2026-10-28',
    goalForecastLatestIso: '2026-11-04',
    poolOnly: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Swim agon populates from store without waiting for sync',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tempRoot = Directory.systemTemp.createTempSync('home_agon_');
    final store = ProgramStore(prefs: prefs, rootOverride: () => tempRoot);
    final controller = ProgramsController(
      store: store,
      prefs: prefs,
      now: () => DateTime(2026, 10, 9),
    );

    addTearDown(() async {
      controller.dispose();
      if (GetIt.I.isRegistered<ProgramsController>()) {
        await GetIt.I.unregister<ProgramsController>();
      }
      try {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      } catch (_) {}
    });

    // Fresh controller starts loading=true / active=null. Dock must still load
    // (old gate was `!loading && active == null`, which never fired).
    expect(controller.loading, isTrue);
    expect(!controller.loading && controller.active == null, isFalse);

    await tester.runAsync(() async {
      await store.activate(_activeProgram());
      await controller.load();
    });
    expect(controller.hasActive, isTrue);

    GetIt.I.registerSingleton<ProgramsController>(controller);

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: HomeSnapshotView(
          snapshot: HomeSnapshot.forPrecedence(HomePrecedence.syncInProgress),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tap to start'), findsNothing);
    expect(find.textContaining('Wk 1 of 3'), findsOneWidget);
    expect(find.textContaining('live'), findsOneWidget);
  });
}
