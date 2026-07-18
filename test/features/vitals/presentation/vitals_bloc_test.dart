import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_state.dart';

class _FakeRepo implements VitalsRepository {
  bool gatePassed = true;
  List<SleepSessionSummary> sleep = const [];
  List<DailyHrDaySummary> hr = const [];
  Either<Failure, VitalsSnapshot>? syncResult;
  int syncCalls = 0;

  @override
  Future<bool> isGateAPassed() async => gatePassed;

  @override
  bool get isSyncOrMergeInFlight => false;

  @override
  Future<List<SleepSessionSummary>> loadSleepSessions() async => sleep;

  @override
  Future<List<DailyHrDaySummary>> loadDailyHr() async => hr;

  @override
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch() async {
    syncCalls++;
    return syncResult ??
        Right(
          VitalsSnapshot(sleepSessions: sleep, dailyHr: hr),
        );
  }

  @override
  Future<void> clearLocal() async {
    sleep = const [];
    hr = const [];
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
    expect(bloc.state.message, contains('Gate A'));
    await bloc.close();
  });

  test('busy surfaces non-destructive message', () async {
    final repo = _FakeRepo()
      ..sleep = const [
        SleepSessionSummary(beginUnix: 100, endUnix: 200),
      ]
      ..syncResult = const Left(
        ServerFailure('Another Sync is already in progress'),
      );
    final bloc = VitalsBloc(repository: repo);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    bloc.add(const VitalsSyncRequested());
    await pumpEventQueue();
    expect(bloc.state.sleepSessions, hasLength(1));
    expect(bloc.state.message, contains('Workout Sync'));
    await bloc.close();
  });

  test('stuck keeps list and reconnect guidance phase', () async {
    final repo = _FakeRepo()
      ..syncResult = const Right(
        VitalsSnapshot(
          sleepSessions: [
            SleepSessionSummary(beginUnix: 100, endUnix: 200),
          ],
          dailyHr: [],
          partial: true,
          message: 'Partial sync',
        ),
      );
    final bloc = VitalsBloc(repository: repo);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    bloc.add(const VitalsSyncRequested());
    await pumpEventQueue();
    expect(bloc.state.phase, VitalsPhase.stuck);
    expect(bloc.state.sleepSessions, hasLength(1));
    await bloc.close();
  });

  test('reload after forget clears stale rows', () async {
    final repo = _FakeRepo()
      ..sleep = const [
        SleepSessionSummary(beginUnix: 100, endUnix: 200),
      ];
    final bloc = VitalsBloc(repository: repo);
    bloc.add(const VitalsStarted());
    await pumpEventQueue();
    expect(bloc.state.sleepSessions, hasLength(1));

    await repo.clearLocal();
    bloc.add(const VitalsReloadRequested());
    await pumpEventQueue();
    expect(bloc.state.sleepSessions, isEmpty);
    await bloc.close();
  });
}

Future<void> pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
