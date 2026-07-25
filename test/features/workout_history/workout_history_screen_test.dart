import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
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
}

WorkoutSummary _swim({
  required int number,
  required int startTime,
  required int durationSec,
  int? distanceM,
  int? avgSwolf,
  String? sessionFlag,
  int type = 6,
}) {
  return WorkoutSummary(
    number: number,
    startTime: startTime,
    endTime: startTime + durationSec,
    durationSec: durationSec,
    type: type,
    distanceM: distanceM,
    avgSwolf: avgSwolf,
    sessionFlag: sessionFlag,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkoutHistoryBloc bloc;

  final fixtures = [
    _swim(
      number: 11,
      startTime: DateTime(2026, 7, 24, 7, 12).millisecondsSinceEpoch ~/ 1000,
      durationSec: 42 * 60 + 18,
      distanceM: 1250,
      avgSwolf: 41,
      sessionFlag: 'Pace decay after interval 3',
    ),
    _swim(
      number: 10,
      startTime: DateTime(2026, 7, 22, 18, 40).millisecondsSinceEpoch ~/ 1000,
      durationSec: 34 * 60 + 5,
      distanceM: 1000,
      avgSwolf: 39,
    ),
    const WorkoutSummary(
      number: 99,
      startTime: 1,
      endTime: 2,
      durationSec: 60,
      type: 2,
      distanceM: 5000,
    ),
  ];

  setUp(() async {
    bloc = WorkoutHistoryBloc(repository: _FakeRepo(fixtures));
    final loaded = bloc.stream.firstWhere((s) => s.workouts.isNotEmpty);
    bloc.add(const WorkoutHistoryStarted());
    await loaded;
  });

  tearDown(() async {
    await bloc.close();
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

  testWidgets('Swim list shows fixture session rows', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Pool swim · #11'), findsOneWidget);
    expect(find.text('Pool swim · #10'), findsOneWidget);
    expect(find.text('1,250 m'), findsOneWidget);
    expect(find.text('42:18'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('Pace decay after interval 3'), findsOneWidget);
    expect(find.textContaining('#99'), findsNothing);
  });

  testWidgets('tapping a swim row opens detail route', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Pool swim · #11'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Session charts and diagnoses'),
      findsOneWidget,
    );
    expect(find.text('1,250 m'), findsOneWidget);
    expect(find.text('Pool swim · #11'), findsWidgets);
  });

  testWidgets('Run and Strength show empty scaffolding', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Run sessions will list here'),
      findsOneWidget,
    );
    expect(find.text('Empty · OK'), findsOneWidget);
    expect(find.text('Pool swim · #11'), findsNothing);

    await tester.tap(find.text('Strength'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Strength history stays off Swim'),
      findsOneWidget,
    );
    expect(find.text('Empty · OK'), findsOneWidget);
  });
}
