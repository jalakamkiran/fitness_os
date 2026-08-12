import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_history_screen.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_tab_screen.dart';

class _FakeRepo implements VitalsRepository {
  _FakeRepo({
    this.sessions = const [],
    Map<String, String>? feelAnswers,
  }) : feelAnswers = feelAnswers ?? {};

  List<SleepSessionSummary> sessions;
  final Map<String, String> feelAnswers;
  int saveFeelCalls = 0;

  @override
  Future<bool> isGateAPassed() async => true;

  @override
  bool get isSyncOrMergeInFlight => false;

  @override
  bool get sessionReady => true;

  @override
  Future<List<SleepSessionSummary>> loadSleepSessions() async => sessions;

  @override
  Future<List<SleepStageSummary>> loadSleepStages(
    SleepSessionSummary session,
  ) async =>
      const [];

  @override
  Future<List<DailyHrDaySummary>> loadDailyHr() async => const [];

  @override
  Future<List<DailyHrSample>> loadDailyHrSeries(String dayKey) async =>
      const [];

  @override
  Future<List<DailyHrSample>> loadSleepHrWindow({
    required int beginUnix,
    required int endUnix,
  }) async =>
      const [];

  @override
  Future<bool> isSleepEnrichPresent(SleepSessionSummary session) async =>
      false;

  @override
  Future<String?> loadFeelOnWake(SleepSessionSummary session) async =>
      feelAnswers[session.mergeKey];

  @override
  Future<void> saveFeelOnWake(
    SleepSessionSummary session,
    String answer,
  ) async {
    saveFeelCalls++;
    if (feelAnswers.containsKey(session.mergeKey)) return;
    feelAnswers[session.mergeKey] = answer;
  }

  @override
  Future<List<SleepSessionSummary>> loadSleepSessionsForMonth({
    required int year,
    required int month,
  }) async {
    return sessions.where((s) {
      final end = DateTime.fromMillisecondsSinceEpoch(s.endUnix * 1000);
      return end.year == year && end.month == month;
    }).toList();
  }

  @override
  Future<List<FitnessTotalsDay>> loadFitnessTotals() async => const [];

  @override
  Future<FitnessTotalsDay?> loadFitnessTotalsForDay(String dayKey) async =>
      null;

  @override
  Future<AutoTrackingEnableResult?> loadLastEnable() async => null;

  @override
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch() async =>
      Right(VitalsSnapshot(sleepSessions: sessions, dailyHr: const []));

  @override
  Future<Either<Failure, AutoTrackingEnableResult>> enableAutoTracking() async =>
      const Right(
        AutoTrackingEnableResult(
          status: AutoTrackingEnableStatus.ok,
          overall: AutoTrackingOverall.noneArmed,
          features: [],
        ),
      );

  @override
  Future<void> clearLocal() async {}
}

/// Overnight ending "today" in local time.
SleepSessionSummary _todayOvernight() {
  final now = DateTime.now();
  final endLocal = DateTime(now.year, now.month, now.day, 6, 30);
  final beginLocal = endLocal.subtract(const Duration(hours: 7, minutes: 12));
  return SleepSessionSummary(
    beginUnix: beginLocal.toUtc().millisecondsSinceEpoch ~/ 1000,
    endUnix: endLocal.toUtc().millisecondsSinceEpoch ~/ 1000,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('feel-on-wake shows once then hides after answer', (tester) async {
    final session = _todayOvernight();
    final repo = _FakeRepo(sessions: [session]);
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: BlocProvider.value(
          value: bloc,
          child: Scaffold(
            body: SleepTabScreen(repository: repo),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('How do you feel waking up?'), findsOneWidget);

    await tester.tap(find.text('Good'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.saveFeelCalls, 1);
    expect(repo.feelAnswers[session.mergeKey], 'good');
    expect(find.text('How do you feel waking up?'), findsNothing);

    // Rebuild — survey stays hidden (once-per-key).
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: BlocProvider.value(
          value: bloc,
          child: Scaffold(
            body: SleepTabScreen(repository: repo),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('How do you feel waking up?'), findsNothing);
    expect(repo.saveFeelCalls, 1);
  });

  testWidgets('history month arrows change listed sessions', (tester) async {
    final aug = SleepSessionSummary(
      beginUnix: DateTime.utc(2026, 8, 8, 18).millisecondsSinceEpoch ~/ 1000,
      endUnix: DateTime.utc(2026, 8, 9, 1).millisecondsSinceEpoch ~/ 1000,
    );
    final jul = SleepSessionSummary(
      beginUnix: DateTime.utc(2026, 7, 10, 18).millisecondsSinceEpoch ~/ 1000,
      endUnix: DateTime.utc(2026, 7, 11, 1).millisecondsSinceEpoch ~/ 1000,
    );
    final repo = _FakeRepo(sessions: [aug, jul]);

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: SleepHistoryScreen(
          repository: repo,
          initialYear: 2026,
          initialMonth: 8,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Aug 2026'), findsOneWidget);
    expect(find.text('charts later · list first'), findsOneWidget);
    // One session card for August.
    expect(find.byType(Card), findsWidgets);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Jul 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Jun 2026'), findsOneWidget);
    expect(
      find.textContaining('No sleep sessions stored yet'),
      findsOneWidget,
    );
  });

  testWidgets('sleep list empty honesty copy', (tester) async {
    final repo = _FakeRepo();
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: BlocProvider.value(
          value: bloc,
          child: Scaffold(
            body: SleepTabScreen(repository: repo),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('No sleep sessions stored yet'),
      findsOneWidget,
    );
    expect(find.text('Advanced sleep metrics — unlock soon'), findsOneWidget);
    expect(
      find.text('no fake metrics · quality score deferred'),
      findsOneWidget,
    );
  });
}
