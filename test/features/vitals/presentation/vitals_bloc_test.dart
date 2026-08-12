import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/vitals/domain/morning_wellness.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_state.dart';

class _FakeRepo implements VitalsRepository {
  bool gatePassed = true;
  bool sessionReadyFlag = true;
  List<SleepSessionSummary> sleep = const [];
  List<DailyHrDaySummary> hr = const [];
  Either<Failure, VitalsSnapshot>? syncResult;
  Either<Failure, AutoTrackingEnableResult>? enableResult;
  AutoTrackingEnableResult? lastEnable;
  int syncCalls = 0;
  int enableCalls = 0;

  @override
  Future<bool> isGateAPassed() async => gatePassed;

  @override
  bool get isSyncOrMergeInFlight => false;

  @override
  bool get sessionReady => sessionReadyFlag;

  @override
  Future<List<SleepSessionSummary>> loadSleepSessions() async => sleep;

  @override
  Future<List<SleepStageSummary>> loadSleepStages(
    SleepSessionSummary session,
  ) async =>
      session.stages;

  @override
  Future<List<DailyHrDaySummary>> loadDailyHr() async => hr;

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
  Future<MorningWellness?> loadMorningWellness(
    SleepSessionSummary session,
  ) async =>
      null;

  @override
  Future<void> saveMorningWellness(
    SleepSessionSummary session,
    MorningWellness wellness,
  ) async {}

  @override
  Future<List<SleepSessionSummary>> loadSleepSessionsForMonth({
    required int year,
    required int month,
  }) async =>
      sleep;

  @override
  Future<List<FitnessTotalsDay>> loadFitnessTotals() async => const [];

  @override
  Future<FitnessTotalsDay?> loadFitnessTotalsForDay(String dayKey) async =>
      null;

  @override
  Future<AutoTrackingEnableResult?> loadLastEnable() async => lastEnable;

  @override
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch() async {
    syncCalls++;
    return syncResult ??
        Right(
          VitalsSnapshot(sleepSessions: sleep, dailyHr: hr),
        );
  }

  @override
  Future<Either<Failure, AutoTrackingEnableResult>> enableAutoTracking() async {
    enableCalls++;
    return enableResult ??
        const Right(
          AutoTrackingEnableResult(
            status: AutoTrackingEnableStatus.ok,
            overall: AutoTrackingOverall.allArmed,
            features: [
              AutoTrackingFeatureOutcome(id: 'trusleep', outcome: 'armed'),
              AutoTrackingFeatureOutcome(id: 'auto_hr', outcome: 'armed'),
              AutoTrackingFeatureOutcome(id: 'auto_spo2', outcome: 'armed'),
            ],
          ),
        );
  }

  @override
  Future<void> clearLocal() async {
    sleep = const [];
    hr = const [];
    lastEnable = null;
  }
}

void main() {
  test('loaded state shows sleep + HR after successful sync', () async {
    final repo = _FakeRepo()
      ..syncResult = const Right(
        VitalsSnapshot(
          sleepSessions: [
            SleepSessionSummary(beginUnix: 100, endUnix: 200),
          ],
          dailyHr: [
            DailyHrDaySummary(
              dayKey: '2023-11-14',
              minBpm: 60,
              avgBpm: 70,
              maxBpm: 80,
              sampleCount: 3,
            ),
          ],
        ),
      );
    final bloc = VitalsBloc(repository: repo);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    bloc.add(const VitalsSyncRequested());
    await pumpEventQueue();

    expect(bloc.state.sleepSessions, hasLength(1));
    expect(bloc.state.latestHrDay?.avgBpm, 70);
    expect(bloc.state.phase, VitalsPhase.idle);
    await bloc.close();
  });

  test('gate incomplete → Sync blocked', () async {
    final repo = _FakeRepo()..gatePassed = false;
    final bloc = VitalsBloc(repository: repo);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    expect(bloc.state.phase, VitalsPhase.blocked);
    bloc.add(const VitalsSyncRequested());
    await pumpEventQueue();
    expect(repo.syncCalls, 0);
    await bloc.close();
  });

  test('busy sync maps to workout sync copy', () async {
    final repo = _FakeRepo()
      ..syncResult = const Left(
        ServerFailure('Another Sync is already in progress'),
      );
    final bloc = VitalsBloc(repository: repo);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    bloc.add(const VitalsSyncRequested());
    await pumpEventQueue();
    expect(bloc.state.message, contains('Workout Sync'));
    await bloc.close();
  });

  test('enable success stores last-run and wear next-step', () async {
    final repo = _FakeRepo();
    final bloc = VitalsBloc(repository: repo);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    bloc.add(const VitalsEnableRequested());
    await pumpEventQueue();

    expect(repo.enableCalls, 1);
    expect(bloc.state.lastEnable?.overall, AutoTrackingOverall.allArmed);
    expect(bloc.state.enableNextStep, contains('does not refill whole-day HR'));
    expect(bloc.state.phase, VitalsPhase.idle);
    expect(bloc.state.sleepSessions, isEmpty);
    await bloc.close();
  });

  test('enable disabled when session not ready', () async {
    final repo = _FakeRepo()..sessionReadyFlag = false;
    final bloc = VitalsBloc(repository: repo);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    expect(bloc.state.enableDisabled, isTrue);
    bloc.add(const VitalsEnableRequested());
    await pumpEventQueue();
    expect(repo.enableCalls, 0);
    await bloc.close();
  });

  test('enabling disables sync; sync during enable is ignored', () async {
    final delayed = _DelayedEnableRepo();
    final bloc = VitalsBloc(repository: delayed);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    bloc.add(const VitalsEnableRequested());
    await pumpEventQueue();
    expect(bloc.state.phase, VitalsPhase.enabling);
    expect(bloc.state.syncDisabled, isTrue);
    bloc.add(const VitalsSyncRequested());
    await pumpEventQueue();
    expect(delayed.syncCalls, 0);
    delayed.completeEnable();
    await pumpEventQueue();
    expect(bloc.state.phase, VitalsPhase.idle);
    expect(bloc.state.lastEnable?.overall, AutoTrackingOverall.partial);
    await bloc.close();
  });

  test('re-arm replaces prior last-run', () async {
    final repo = _FakeRepo()
      ..lastEnable = const AutoTrackingEnableResult(
        status: AutoTrackingEnableStatus.ok,
        overall: AutoTrackingOverall.noneArmed,
        features: [
          AutoTrackingFeatureOutcome(id: 'auto_hr', outcome: 'failed'),
        ],
      );
    final bloc = VitalsBloc(repository: repo);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    expect(bloc.state.lastEnable?.overall, AutoTrackingOverall.noneArmed);
    bloc.add(const VitalsEnableRequested());
    await pumpEventQueue();
    expect(bloc.state.lastEnable?.overall, AutoTrackingOverall.allArmed);
    await bloc.close();
  });
}

class _DelayedEnableRepo extends _FakeRepo {
  Completer<Either<Failure, AutoTrackingEnableResult>>? _completer;

  void completeEnable() {
    _completer?.complete(
      const Right(
        AutoTrackingEnableResult(
          status: AutoTrackingEnableStatus.ok,
          overall: AutoTrackingOverall.partial,
          features: [
            AutoTrackingFeatureOutcome(id: 'trusleep', outcome: 'armed'),
            AutoTrackingFeatureOutcome(id: 'auto_hr', outcome: 'armed'),
            AutoTrackingFeatureOutcome(id: 'auto_spo2', outcome: 'skipped'),
          ],
        ),
      ),
    );
  }

  @override
  Future<Either<Failure, AutoTrackingEnableResult>> enableAutoTracking() async {
    enableCalls++;
    _completer = Completer();
    return _completer!.future;
  }
}
