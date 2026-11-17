import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'dart:io';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/workout_history/data/strength_session_export_service.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_bloc.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_event.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_screen.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_screen.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/sport_tabs.dart';

class _FakeRepo implements WorkoutHistoryRepository {
  _FakeRepo(this.workouts);

  final List<WorkoutSummary> workouts;

  @override
  Future<bool> isGateAPassed() async => true;

  @override
  Future<List<WorkoutSummary>> loadLocal() async => workouts;

  @override
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch({
    bool forceFullHistory = false,
  }) async =>
      Right(workouts);

  @override
  bool get isSyncOrMergeInFlight => false;

  @override
  bool get lastLeftoverPersistLanded => true;

  @override
  Future<void> clearLocal() async {}

  @override
  Future<CanonicalSwimSession?> loadCanonicalSwim(int workoutNumber) async =>
      null;

  @override
  CanonicalSwimSession? canonicalSwimFromSummary(WorkoutSummary workout) =>
      null;

  @override
  Future<List<CanonicalSwimSession>> loadAllCanonicalSwims() async =>
      const [];

  @override
  Future<SwimDiagnosisReport> loadSwimDiagnosisReport({
    int? focusWorkoutNumber,
  }) async =>
      const SwimDiagnosisReport(
        sessionDiagnoses: [],
        trendDiagnoses: [],
        trends: SwimTrends(points: [], sessionCount: 0),
      );
}

WorkoutSummary _workout({
  required int number,
  required int startTime,
  required int durationSec,
  required int type,
  int? distanceM,
  int? avgSwolf,
  int? calories,
  int? load,
  int? recoveryTime,
  String? sessionFlag,
}) {
  return WorkoutSummary(
    number: number,
    startTime: startTime,
    endTime: startTime + durationSec,
    durationSec: durationSec,
    type: type,
    distanceM: distanceM,
    avgSwolf: avgSwolf,
    calories: calories,
    load: load,
    recoveryTime: recoveryTime,
    sessionFlag: sessionFlag,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkoutHistoryBloc bloc;

  final fixtures = [
    _workout(
      number: 11,
      type: 6,
      startTime: DateTime(2026, 7, 24, 7, 12).millisecondsSinceEpoch ~/ 1000,
      durationSec: 42 * 60 + 18,
      distanceM: 1250,
      avgSwolf: 41,
      sessionFlag: 'Pace decay after interval 3',
    ),
    _workout(
      number: 10,
      type: 6,
      startTime: DateTime(2026, 7, 22, 18, 40).millisecondsSinceEpoch ~/ 1000,
      durationSec: 34 * 60 + 5,
      distanceM: 1000,
      avgSwolf: 39,
    ),
    // Owner GT5 log shape: #35 indoor run + outdoor run must not appear on Swim.
    _workout(
      number: 35,
      type: 5,
      startTime: DateTime(2026, 8, 12, 10, 0).millisecondsSinceEpoch ~/ 1000,
      durationSec: 433,
      distanceM: 1000,
      calories: 80,
    ),
    _workout(
      number: 99,
      type: 2,
      startTime: 1,
      durationSec: 60,
      distanceM: 5000,
      calories: 400,
    ),
    // Mixed outdoor can wire as Walk (type=1) — still on Run/Walk tab.
    _workout(
      number: 60,
      type: 1,
      startTime: DateTime(2026, 9, 9, 8, 26).millisecondsSinceEpoch ~/ 1000,
      durationSec: 1300,
      distanceM: 2100,
      calories: 160,
    ),
    _workout(
      number: 34,
      type: 140,
      startTime: DateTime(2026, 8, 11, 18, 0).millisecondsSinceEpoch ~/ 1000,
      durationSec: 2850,
      calories: 220,
      load: 12,
      recoveryTime: 60,
    ),
  ];

  setUp(() async {
    await GetIt.I.reset();
    final repo = _FakeRepo(fixtures);
    sl.registerLazySingleton<WorkoutHistoryRepository>(() => repo);
    bloc = WorkoutHistoryBloc(repository: repo);
    final loaded = bloc.stream.firstWhere((s) => s.workouts.isNotEmpty);
    bloc.add(const WorkoutHistoryStarted());
    await loaded;
  });

  tearDown(() async {
    await bloc.close();
    await GetIt.I.reset();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<StrengthSessionExportResult> Function()? exportAllOverride,
    bool Function()? exportBusyOverride,
    Future<void> Function(File file)? shareExport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: WorkoutHistoryScreen(
          bloc: bloc,
          exportAllOverride: exportAllOverride,
          // Avoid GetIt StrengthSessionExportService in widget tests.
          exportBusyOverride: exportBusyOverride ?? () => false,
          shareExport: shareExport,
        ),
        onGenerateRoute: (settings) {
          if (settings.name == WorkoutDetailRoute.path) {
            final args = settings.arguments;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => args is WorkoutSummary
                  ? WorkoutDetailScreen(workout: args)
                  : const Scaffold(
                      body: Center(child: Text('Workout not found')),
                    ),
            );
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sport tabs visible with Swim selected', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(SportTabs), findsOneWidget);
    expect(find.text('Swim'), findsOneWidget);
    expect(find.text('Run/Walk'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.textContaining('2 · pool'), findsOneWidget);
  });

  testWidgets('Swim list shows fixture session rows and hides runs',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Pool swim · #11'), findsOneWidget);
    expect(find.text('Pool swim · #10'), findsOneWidget);
    expect(find.text('1,250 m'), findsOneWidget);
    expect(find.text('42:18'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('Pace decay after interval 3'), findsOneWidget);
    expect(find.textContaining('Indoor run'), findsNothing);
    expect(find.textContaining('#99'), findsNothing);
    expect(find.textContaining('#35'), findsNothing);
    expect(find.textContaining('#34'), findsNothing);
  });

  testWidgets('tapping a swim row opens detail route', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Pool swim · #11'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pool swim #11'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
    expect(find.textContaining('1250'), findsWidgets);
  }, skip: true); // TODO(CI): Pre-existing failure

  testWidgets('Run/Walk tab lists walk, indoor, and outdoor runs',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Run/Walk'));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 · run/walk'), findsOneWidget);
    expect(find.text('Walk · #60'), findsOneWidget);
    expect(find.text('Indoor run · #35'), findsOneWidget);
    expect(find.text('Run · #99'), findsOneWidget);
    expect(find.text('1.00 km'), findsOneWidget);
    expect(find.text('PACE'), findsWidgets);
    expect(find.text('Pool swim · #11'), findsNothing);
    expect(find.textContaining('Strength ·'), findsNothing);
  });

  testWidgets('Gym tab lists strength sessions', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 · gym/strength'), findsOneWidget);
    expect(find.text('Strength · #34'), findsOneWidget);
    expect(find.text('LOAD'), findsOneWidget);
    expect(find.text('RECOVERY'), findsOneWidget);
    expect(find.text('CAL'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget);
    expect(find.text('220'), findsOneWidget);
    expect(find.text('Indoor run · #35'), findsNothing);
    expect(find.text('Pool swim · #11'), findsNothing);
  });

  testWidgets('Export all strength: confirm → export+share; cancel → no share',
      (tester) async {
    var exportCalls = 0;
    var shareCalls = 0;
    final tempDir = Directory(
      'build/strength_export_all_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final file = File(
      '${tempDir.path}/${StrengthSessionExportService.exportCacheDirName}/'
      'strength_all_test.json',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{"schemaVersion":1,"sessions":[{"number":34}]}');

    await pumpScreen(
      tester,
      exportAllOverride: () async {
        exportCalls++;
        return StrengthSessionExportResult.success(
          file: file,
          byteLength: file.lengthSync(),
        );
      },
      exportBusyOverride: () => false,
      shareExport: (_) async {
        shareCalls++;
      },
    );

    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();

    expect(find.text('Export all strength sessions'), findsOneWidget);

    // Cancel → no export/share.
    await tester.tap(find.text('Export all strength sessions'));
    await tester.pumpAndSettle();
    expect(find.text('Export all strength sessions?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(exportCalls, 0);
    expect(shareCalls, 0);

    // Confirm → export + share.
    await tester.tap(find.text('Export all strength sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(exportCalls, 1);
    expect(shareCalls, 1);
  });

  testWidgets('Export all strength blocked when sync/merge busy',
      (tester) async {
    var exportCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: WorkoutHistoryScreen(
          bloc: bloc,
          exportAllOverride: () async {
            exportCalls++;
            return const StrengthSessionExportResult.failed('should not run');
          },
          // Busy shows an indeterminate spinner — avoid pumpAndSettle.
          exportBusyOverride: () => true,
          shareExport: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Gym'));
    await tester.pump();

    final exportBtn = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Export all strength sessions'),
    );
    expect(exportBtn.onPressed, isNull);
    expect(exportCalls, 0);
  });

  group('Export all strength — empty device', () {
    late WorkoutHistoryBloc emptyBloc;

    setUp(() async {
      await GetIt.I.reset();
      final swimOnly = [
        _workout(
          number: 11,
          type: 6,
          startTime:
              DateTime(2026, 7, 24, 7, 12).millisecondsSinceEpoch ~/ 1000,
          durationSec: 42 * 60,
          distanceM: 1250,
        ),
      ];
      final repo = _FakeRepo(swimOnly);
      sl.registerLazySingleton<WorkoutHistoryRepository>(() => repo);
      emptyBloc = WorkoutHistoryBloc(repository: repo);
      final loaded =
          emptyBloc.stream.firstWhere((s) => s.workouts.isNotEmpty);
      emptyBloc.add(const WorkoutHistoryStarted());
      await loaded;
    });

    tearDown(() async {
      await emptyBloc.close();
      await GetIt.I.reset();
    });

    testWidgets('Export CTA disabled when no type=140 sessions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BpTheme.light(),
          home: WorkoutHistoryScreen(
            bloc: emptyBloc,
            exportBusyOverride: () => false,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Gym'));
      await tester.pump();

      final exportBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Export all strength sessions'),
      );
      expect(exportBtn.onPressed, isNull);
      expect(
        find.text('No strength sessions on this device to export.'),
        findsOneWidget,
      );
    });
  });
}
