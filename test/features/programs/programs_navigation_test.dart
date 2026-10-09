import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/domain/baseline.dart' as prog;
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_create_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_navigation.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_progress_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_proof_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_session_screen.dart';

Program _program() {
  return Program(
    id: 'p-nav',
    intake: const ProgramIntake(
      goalDistanceM: 1200,
      horizonWeeks: 3,
      sessionsPerWeek: 3,
      poolOnlyAcknowledged: true,
    ),
    status: ProgramStatus.active,
    createdAtMs: 1,
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
        programId: 'p-nav',
        dayIso: '2026-10-09',
        role: ChoreRole.endurance,
        state: ChoreState.scheduled,
        targetDistanceM: 900,
        blocks: [
          ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 200),
          ChoreBlock(part: 'main', label: 'Main', distanceM: 500),
          ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 200),
        ],
      ),
    ],
    poolOnly: true,
    activatedAtMs: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late ProgramsController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tempRoot = Directory.systemTemp.createTempSync('programs_nav_');
    final store = ProgramStore(prefs: prefs, rootOverride: () => tempRoot);
    await store.activate(_program());
    controller = ProgramsController(
      store: store,
      prefs: prefs,
      now: () => DateTime(2026, 10, 9),
    );
    await controller.load();
  });

  tearDown(() {
    controller.dispose();
    try {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpHost(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('openSession pushes ProgramsSessionScreen', (tester) async {
    await pumpHost(
      tester,
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: () => ProgramsNavigation.openSession(
              context,
              controller: controller,
              choreId: 'c1',
            ),
            child: const Text('go'),
          );
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(ProgramsSessionScreen), findsOneWidget);
  });

  testWidgets('openProof with milestoneId pushes ProgramsProofScreen',
      (tester) async {
    await pumpHost(
      tester,
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: () => ProgramsNavigation.openProof(
              context,
              controller: controller,
              milestoneId: 'm1',
            ),
            child: const Text('go'),
          );
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(ProgramsProofScreen), findsOneWidget);
  });

  testWidgets('openProof null milestone falls back to session', (tester) async {
    await pumpHost(
      tester,
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: () => ProgramsNavigation.openProof(
              context,
              controller: controller,
              milestoneId: null,
              fallbackChoreId: 'c1',
            ),
            child: const Text('go'),
          );
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(ProgramsSessionScreen), findsOneWidget);
  });

  testWidgets('openProof with nothing returns false no-op', (tester) async {
    var opened = true;
    await pumpHost(
      tester,
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: () async {
              opened = await ProgramsNavigation.openProof(
                context,
                controller: controller,
              );
            },
            child: const Text('go'),
          );
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(opened, isFalse);
    expect(find.byType(ProgramsProofScreen), findsNothing);
    expect(find.byType(ProgramsSessionScreen), findsNothing);
  });

  testWidgets('openCreate pushes ProgramsCreateScreen', (tester) async {
    await pumpHost(
      tester,
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: () => ProgramsNavigation.openCreate(
              context,
              controller: controller,
            ),
            child: const Text('create'),
          );
        },
      ),
    );
    await tester.tap(find.text('create'));
    await tester.pumpAndSettle();
    expect(find.byType(ProgramsCreateScreen), findsOneWidget);
  });

  testWidgets('openOdyssey pushes ProgramsProgressScreen', (tester) async {
    await pumpHost(
      tester,
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: () => ProgramsNavigation.openOdyssey(
              context,
              controller: controller,
            ),
            child: const Text('odyssey'),
          );
        },
      ),
    );
    await tester.tap(find.text('odyssey'));
    await tester.pumpAndSettle();
    expect(find.byType(ProgramsProgressScreen), findsOneWidget);
  });
}
