import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
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
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch() async =>
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
    _workout(
      number: 34,
      type: 140,
      startTime: DateTime(2026, 8, 11, 18, 0).millisecondsSinceEpoch ~/ 1000,
      durationSec: 2850,
      calories: 220,
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

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: WorkoutHistoryScreen(bloc: bloc),
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
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
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
  });

  testWidgets('Run tab lists indoor and outdoor runs', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 · run'), findsOneWidget);
    expect(find.text('Indoor run · #35'), findsOneWidget);
    expect(find.text('Run · #99'), findsOneWidget);
    expect(find.text('1,000 m'), findsOneWidget);
    expect(find.text('80'), findsOneWidget); // calories
    expect(find.text('Pool swim · #11'), findsNothing);
    expect(find.textContaining('Strength ·'), findsNothing);
  });

  testWidgets('Strength tab lists strength sessions', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Strength'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 · strength'), findsOneWidget);
    expect(find.text('Strength · #34'), findsOneWidget);
    expect(find.text('220'), findsOneWidget);
    expect(find.text('Indoor run · #35'), findsNothing);
    expect(find.text('Pool swim · #11'), findsNothing);
  });
}
