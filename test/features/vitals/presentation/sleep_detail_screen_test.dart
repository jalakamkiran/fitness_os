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
    this.hr = const [],
    this.enrichPresent = false,
  });

  final List<SleepStageSummary> stages;
  final List<DailyHrSample> hr;
  final bool enrichPresent;

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
      hr;

  @override
  Future<bool> isSleepEnrichPresent(SleepSessionSummary session) async =>
      enrichPresent;

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
  // Local overnight approx: previous 23:00 → 06:30 next day (UTC-ish fixture).
  final begin = DateTime.utc(2026, 8, 8, 17, 48); // ~23:18 IST
  final end = DateTime.utc(2026, 8, 9, 1, 0); // ~06:30 IST
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
  final hr = [
    for (var i = 0; i < 12; i++)
      DailyHrSample(
        timestampUnix: session.beginUnix + i * 600,
        bpm: 50 + i,
      ),
  ];

  testWidgets('stages + HR render; no Quality score', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: SleepDetailScreen(
          session: session,
          repository: _FakeRepo(stages: stages, hr: hr),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Stage structure'), findsOneWidget);
    expect(find.text('Stage mix'), findsOneWidget);
    expect(find.text('Continuous HR'), findsOneWidget);
    expect(find.text('Light'), findsWidgets);
    expect(find.text('Deep'), findsWidgets);
    expect(find.textContaining('Quality'), findsNothing);
    expect(find.text('Continuous HR'), findsOneWidget);
    expect(find.text('TruSleep enrich'), findsNothing);
  });

  testWidgets('no enrich → no TruSleep toggle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: SleepDetailScreen(
          session: session,
          repository: _FakeRepo(stages: stages, hr: hr, enrichPresent: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('TruSleep enrich'), findsNothing);
    expect(find.text('Continuous HR'), findsOneWidget);
  });

  testWidgets('enrich present → toggle; TruSleep mode honesty', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: SleepDetailScreen(
          session: session,
          repository: _FakeRepo(stages: stages, hr: hr, enrichPresent: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('sleep_mode_trusleep')), findsOneWidget);
    expect(find.text('Continuous HR'), findsWidgets);

    final truSleepTab = find.byKey(const ValueKey('sleep_mode_trusleep'));
    await tester.ensureVisible(truSleepTab);
    await tester.tap(truSleepTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('TruSleep file on device · enrich preview'),
      findsOneWidget,
    );
    expect(
      find.text('PPG decode deferred · not a BPM claim'),
      findsOneWidget,
    );
  });

  testWidgets('empty stages + empty HR honesty copy', (tester) async {
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
    expect(
      find.textContaining('Overnight HR needs auto-HR armed and wear'),
      findsOneWidget,
    );
    expect(find.text('wear → Enable auto-HR → Sync'), findsOneWidget);
  });

  testWidgets('stages only shows HR guidance with stages-synced copy',
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

    expect(
      find.text(
        'Stages synced. Overnight HR needs auto-HR armed and wear — '
        'Sync again after.',
      ),
      findsOneWidget,
    );
  });
}
