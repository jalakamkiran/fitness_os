import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_detail_screen.dart';

class _FakeRepo implements VitalsRepository {
  _FakeRepo({
    this.stages = const [],
    this.summary,
  });

  final List<SleepStageSummary> stages;
  final TruSleepSequenceSession? summary;

  @override
  Future<bool> isGateAPassed() async => true;

  @override
  bool get isSyncOrMergeInFlight => false;

  @override
  bool get sessionReady => true;

  @override
  Future<List<SleepSessionSummary>> loadSleepSessions() async => const [];

  @override
  Future<List<SleepStageSummary>> loadSleepStages(
    SleepSessionSummary session,
  ) async =>
      stages;

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
  Future<TruSleepSequenceSession?> loadTruSleepSummary(
    SleepSessionSummary session,
  ) async =>
      summary;


  @override
  Future<String?> loadFeelOnWake(SleepSessionSummary session) async => null;

  @override
  Future<void> saveFeelOnWake(
    SleepSessionSummary session,
    String answer,
  ) async {}

  @override
  Future<List<SleepSessionSummary>> loadSleepSessionsForMonth({
    required int year,
    required int month,
  }) async =>
      const [];

  @override
  Future<List<FitnessTotalsDay>> loadFitnessTotals() async => const [];

  @override
  Future<FitnessTotalsDay?> loadFitnessTotalsForDay(String dayKey) async =>
      null;

  @override
  Future<AutoTrackingEnableResult?> loadLastEnable() async => null;

  @override
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch() async =>
      const Right(VitalsSnapshot(sleepSessions: [], dailyHr: []));

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

SleepSessionSummary _overnight() {
  final begin = DateTime.utc(2026, 8, 8, 17, 48);
  final end = DateTime.utc(2026, 8, 9, 1, 0);
  return SleepSessionSummary(
    beginUnix: begin.millisecondsSinceEpoch ~/ 1000,
    endUnix: end.millisecondsSinceEpoch ~/ 1000,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final session = _overnight();
  final stages = [
    SleepStageSummary(
      timestampUnix: session.beginUnix,
      durationMin: 40,
      wireType: 1,
    ),
    SleepStageSummary(
      timestampUnix: session.beginUnix + 40 * 60,
      durationMin: 30,
      wireType: 2,
    ),
    SleepStageSummary(
      timestampUnix: session.beginUnix + 70 * 60,
      durationMin: 25,
      wireType: 3,
    ),
    SleepStageSummary(
      timestampUnix: session.beginUnix + 95 * 60,
      durationMin: 10,
      wireType: 4,
    ),
  ];

  testWidgets('stages render without continuous-HR mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: SleepDetailScreen(
          session: session,
          repository: _FakeRepo(stages: stages),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Stage structure'), findsOneWidget);
    expect(find.text('Stage mix'), findsOneWidget);
    expect(find.text('Light'), findsWidgets);
    expect(find.text('Deep'), findsWidgets);
    expect(find.textContaining('Quality'), findsNothing);
    expect(find.text('Continuous HR'), findsNothing);
    expect(find.byKey(const ValueKey('sleep_mode_continuous_hr')), findsNothing);
    expect(find.text('TruSleep enrich'), findsNothing);
  });

  testWidgets('enrich present no longer introduces TruSleep↔HR toggle',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: SleepDetailScreen(
          session: session,
          repository: _FakeRepo(stages: stages),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('sleep_mode_trusleep')), findsNothing);
    expect(find.byKey(const ValueKey('sleep_mode_continuous_hr')), findsNothing);
    expect(find.text('Continuous HR'), findsNothing);
  });

  testWidgets('empty stages honesty without HR refill copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: SleepDetailScreen(
          session: session,
          repository: _FakeRepo(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.textContaining('No stage blocks for this session'),
      findsOneWidget,
    );
    expect(find.textContaining('Overnight HR'), findsNothing);
    expect(find.text('wear → Enable auto-HR → Sync'), findsNothing);
    expect(find.text('Continuous HR'), findsNothing);
  });

  testWidgets('TruSleep summary shows score and KPIs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: SleepDetailScreen(
          session: session,
          repository: _FakeRepo(
            stages: stages,
            summary: TruSleepSequenceSession(
              beginUnix: session.beginUnix,
              endUnix: session.endUnix,
              sleepScore: 84,
              avgHrv: 42,
              avgHeartRate: 58,
              sleepEfficiency: 98,
              sleepLatencySec: 8 * 60,
              deepPart: 88,
              bedTimeUnix: session.beginUnix - 8 * 60,
              fallAsleepUnix: session.beginUnix,
              wakeupUnix: session.endUnix,
              risingUnix: session.endUnix + 7 * 60,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sleep_score')), findsOneWidget);
    expect(find.text('84'), findsOneWidget);
    expect(find.text('TruSleep'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('HRV'), findsOneWidget);
    expect(find.text('Night landmarks'), findsOneWidget);
    expect(find.text('What drove the night · contributors'), findsOneWidget);
    final advanced = find.text('Advanced sleep metrics', skipOffstage: false);
    await tester.ensureVisible(advanced);
    await tester.pumpAndSettle();
    expect(find.text('Advanced sleep metrics'), findsOneWidget);
    expect(find.text('Deep continuity'), findsOneWidget);
    expect(find.text('Sleep latency'), findsOneWidget);
  });
}
