import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/view/recovery_tab_host.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/recovery_subtabs.dart';

class _FakeRepo implements VitalsRepository {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Recovery host switches Vitals | Sleep without second nav',
      (tester) async {
    final repo = _FakeRepo();
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: RecoveryTabHost(bloc: bloc, repository: repo),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Recovery'), findsWidgets);
    expect(find.byType(RecoverySubtabs), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // Default subtab is Sleep.
    expect(find.text('View historic sleep data'), findsOneWidget);
    expect(find.text('Enable auto-tracking'), findsNothing);

    await tester.tap(find.text('Vitals').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Offstage Sleep still exists in IndexedStack; assert Vitals chrome is present.
    expect(find.text('Enable auto-tracking'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Whole-day heart rate'), findsOneWidget);

    await tester.tap(find.text('Sleep').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('View historic sleep data'), findsOneWidget);
    expect(find.text('Advanced sleep metrics — unlock soon'), findsOneWidget);
  });

  testWidgets('Recovery host includes Food subtab in IndexedStack',
      (tester) async {
    final repo = _FakeRepo();
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: RecoveryTabHost(bloc: bloc, repository: repo),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Food'), findsOneWidget);

    final indexedStack = tester.widget<IndexedStack>(
      find.byType(IndexedStack),
    );
    expect(indexedStack.children.length, 3);
  });

  testWidgets('Food subtab displays Food home without vitals data',
      (tester) async {
    final repo = _FakeRepo();
    final bloc = VitalsBloc(repository: repo)..add(const VitalsStarted());

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: RecoveryTabHost(bloc: bloc, repository: repo),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Food'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Food Logging'), findsOneWidget);
    expect(find.text('Log meal'), findsOneWidget);
    expect(find.text('Set meal times'), findsOneWidget);
  });
}
