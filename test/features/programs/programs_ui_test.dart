import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/domain/baseline.dart' as prog;
import 'package:fitness_os/features/programs/domain/baseline_resolver.dart';
import 'package:fitness_os/features/programs/domain/chore_matcher.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/program_planner.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_create_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_home_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_proof_screen.dart';

Program _prebuiltProgram({
  String id = 'p-ui',
  String choreDay = '2026-10-09',
}) {
  return Program(
    id: id,
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
    chores: [
      ChoreSession(
        id: 'c1',
        programId: id,
        dayIso: choreDay,
        role: ChoreRole.endurance,
        state: ChoreState.scheduled,
        targetDistanceM: 1800,
        focusLine: 'Long steady swim',
        blocks: const [
          ChoreBlock(part: 'warmUp', label: 'WU easy', distanceM: 300),
          ChoreBlock(part: 'main', label: 'Main continuous', distanceM: 1200),
          ChoreBlock(part: 'coolDown', label: 'CD easy', distanceM: 200),
        ],
      ),
    ],
    goalForecastLikelyIso: '2026-10-31',
    goalForecastEarliestIso: '2026-10-28',
    goalForecastLatestIso: '2026-11-04',
    poolOnly: true,
    activatedAtMs: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late SharedPreferences prefs;
  late ProgramStore store;
  late ProgramsController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tempRoot = Directory.systemTemp.createTempSync('programs_ui_');
    store = ProgramStore(prefs: prefs, rootOverride: () => tempRoot);
    controller = ProgramsController(
      store: store,
      prefs: prefs,
      planner: ProgramPlanner(),
      resolver: BaselineResolver(),
      matcher: ChoreMatcher(),
      now: () => DateTime(2026, 10, 9),
    );
  });

  tearDown(() {
    controller.dispose();
    try {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: home,
      ),
    );
    await tester.pump();
  }

  Future<void> activateAndLoad(WidgetTester tester) async {
    await tester.runAsync(() async {
      await store.activate(_prebuiltProgram());
      await controller.load();
    });
  }

  testWidgets('create shows pool-only disclosure', (tester) async {
    await pump(tester, ProgramsCreateScreen(controller: controller));

    expect(
      find.byKey(const Key('programs-pool-only-disclosure')),
      findsOneWidget,
    );
    expect(find.textContaining('Pool only'), findsWidgets);
    expect(find.textContaining('Open-water'), findsOneWidget);
    expect(find.byKey(const Key('programs-pool-only-checkbox')), findsOneWidget);
  });

  testWidgets('create → activate → active home shows milestone + chore',
      (tester) async {
    await activateAndLoad(tester);
    expect(controller.hasActive, isTrue);

    await pump(tester, ProgramsHomeScreen(controller: controller));

    expect(find.byKey(const Key('programs-next-milestone')), findsOneWidget);
    expect(find.textContaining('1,200 m'), findsWidgets);
    expect(find.byKey(const Key('programs-today-chore')), findsOneWidget);
    expect(find.byKey(const Key('programs-chore-structure')), findsOneWidget);
    expect(find.textContaining('WU · Main with rests · CD'), findsOneWidget);
    expect(find.textContaining('Warm-up'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.textContaining('Cool-down'), findsOneWidget);
    expect(find.textContaining('Agon · Pool swim'), findsOneWidget);
  });

  testWidgets('proof fail shows distance fact + slipped date, no shame words',
      (tester) async {
    await activateAndLoad(tester);
    late String slipped;
    await tester.runAsync(() async {
      final updated = await controller.applyProof(
        milestoneId: 'm1',
        outcome: ProofOutcome.fail,
        judgedDistanceM: 1120,
      );
      slipped = updated!.milestones.first.forecastDateIso;
    });

    await pump(
      tester,
      ProgramsProofScreen(
        controller: controller,
        milestoneId: 'm1',
        initialOutcome: ProofOutcome.fail,
        initialJudgedDistanceM: 1120,
        previewResultOnly: true,
        previewSlippedDate: slipped,
      ),
    );

    expect(find.byKey(const Key('programs-proof-fail-result')), findsOneWidget);
    expect(
      find.byKey(const Key('programs-proof-distance-fact')),
      findsOneWidget,
    );
    expect(find.textContaining('1,120 m of 1,200 m'), findsOneWidget);
    expect(
      find.byKey(const Key('programs-proof-slipped-date')),
      findsOneWidget,
    );
    expect(find.textContaining('Next attempt'), findsOneWidget);
    expect(find.textContaining('Not passed'), findsWidgets);

    const shame = [
      'failed you',
      'you failed',
      'shame',
      'pathetic',
      'disappoint',
      '😢',
      '😞',
    ];
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ')
        .toLowerCase();
    for (final word in shame) {
      expect(texts.contains(word.toLowerCase()), isFalse, reason: word);
    }
  });

  testWidgets('AE6 coach-absent: screens pump without Coach DI', (tester) async {
    await pump(tester, ProgramsCreateScreen(controller: controller));
    expect(
      find.byKey(const Key('programs-pool-only-disclosure')),
      findsOneWidget,
    );

    await activateAndLoad(tester);
    await pump(tester, ProgramsHomeScreen(controller: controller));
    expect(find.byKey(const Key('programs-next-milestone')), findsOneWidget);

    await pump(
      tester,
      ProgramsProofScreen(
        controller: controller,
        milestoneId: 'm1',
        initialOutcome: ProofOutcome.pass,
        initialJudgedDistanceM: 1200,
        previewResultOnly: true,
      ),
    );
    expect(find.byKey(const Key('programs-proof-pass-result')), findsOneWidget);
  });
}
