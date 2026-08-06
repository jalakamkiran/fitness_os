import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/home/data/repositories/home_repository_impl.dart';
import 'package:fitness_os/features/home/domain/home_precedence.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubLink extends HuaweiLink {
  _StubLink(this._state);

  LinkState _state;

  @override
  LinkState get state => _state;

  void setState(LinkState next) => _state = next;

  @override
  bool get sessionReady =>
      _state == LinkState.connected || _state == LinkState.gateAIncomplete;
}

class _EmptyWorkouts implements WorkoutHistoryRepository {
  @override
  Future<bool> isGateAPassed() async => true;

  @override
  Future<List<WorkoutSummary>> loadLocal() async => const [];

  @override
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch() async =>
      const Right([]);

  @override
  Future<CanonicalSwimSession?> loadCanonicalSwim(int workoutNumber) async =>
      null;

  @override
  CanonicalSwimSession? canonicalSwimFromSummary(WorkoutSummary workout) =>
      null;

  @override
  Future<List<CanonicalSwimSession>> loadAllCanonicalSwims() async => const [];

  @override
  Future<SwimDiagnosisReport> loadSwimDiagnosisReport({
    int? focusWorkoutNumber,
  }) async =>
      SwimDiagnosisReport(
        sessionDiagnoses: const [],
        trendDiagnoses: const [],
        trends: buildSwimTrends(const []),
      );
}

class _EmptyVitals implements VitalsRepository {
  @override
  Future<bool> isGateAPassed() async => true;

  @override
  bool get isSyncOrMergeInFlight => false;

  @override
  bool get sessionReady => false;

  @override
  Future<List<SleepSessionSummary>> loadSleepSessions() async => const [];

  @override
  Future<List<DailyHrDaySummary>> loadDailyHr() async => const [];

  @override
  Future<List<DailyHrSample>> loadDailyHrSeries(String dayKey) async =>
      const [];

  @override
  Future<AutoTrackingEnableResult?> loadLastEnable() async => null;

  @override
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch() async =>
      const Right(VitalsSnapshot(sleepSessions: [], dailyHr: []));

  @override
  Future<Either<Failure, AutoTrackingEnableResult>> enableAutoTracking() async =>
      const Left(ServerFailure('unused'));

  @override
  Future<void> clearLocal() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HomeRepositoryImpl> repoWith({required LinkState linkState}) async {
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.rememberedName: 'HUAWEI WATCH GT 5-A07',
      GateAPrefs.gateAPassed: true,
      GateAPrefs.homeLastSyncStatus: 'ok',
      GateAPrefs.homeLastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
      GateAPrefs.lastSyncCursor: 1,
    });
    final prefs = await SharedPreferences.getInstance();
    return HomeRepositoryImpl(
      prefs: prefs,
      link: _StubLink(linkState),
      workouts: _EmptyWorkouts(),
      vitals: _EmptyVitals(),
    );
  }

  test(
    'remembered + everSynced + disconnected must not claim connected',
    () async {
      final repo = await repoWith(linkState: LinkState.disconnected);
      final snap = await repo.loadSnapshot();

      expect(snap.precedence, HomePrecedence.noSwimDataYet);
      expect(snap.syncPillLabel, 'Synced');
      expect(snap.syncTitle, 'HUAWEI WATCH GT 5-A07 paired');
      expect(snap.syncTitle.toLowerCase(), isNot(contains('connected')));
      expect(snap.syncCaption.toLowerCase(), contains('session offline'));
    },
  );

  test('sessionReady keeps connected copy for post-sync Home', () async {
    final repo = await repoWith(linkState: LinkState.connected);
    final snap = await repo.loadSnapshot();

    expect(snap.precedence, HomePrecedence.noSwimDataYet);
    expect(snap.syncTitle, 'HUAWEI WATCH GT 5-A07 connected');
    expect(snap.syncCaption, 'Sync healthy · no swim session today');
  });
}
