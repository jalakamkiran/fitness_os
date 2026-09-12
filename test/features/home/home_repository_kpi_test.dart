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
  _StubLink();

  @override
  LinkState get state => LinkState.connected;

  @override
  bool get sessionReady => true;
}

class _Workouts implements WorkoutHistoryRepository {
  _Workouts(this.local);

  final List<WorkoutSummary> local;

  @override
  Future<bool> isGateAPassed() async => true;

  @override
  Future<List<WorkoutSummary>> loadLocal() async => local;

  @override
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch({
    bool forceFullHistory = false,
  }) async =>
      Right(local);

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

class _Vitals implements VitalsRepository {
  _Vitals({this.ftToday, this.loadFailed = false});

  FitnessTotalsDay? ftToday;
  final bool loadFailed;

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
  Future<TruSleepSequenceSession?> loadTruSleepSummary(
    SleepSessionSummary session,
  ) async =>
      null;


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
  Future<List<FitnessTotalsDay>> loadFitnessTotals() async {
    if (loadFailed) return const [];
    final row = ftToday;
    return row == null ? const [] : [row];
  }

  @override
  Future<FitnessTotalsDay?> loadFitnessTotalsForDay(String dayKey) async {
    if (loadFailed) return null;
    final row = ftToday;
    if (row == null || row.dayKey != dayKey) return null;
    return row;
  }

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

  final fixedNow = DateTime(2026, 8, 8, 23, 20);

  String dayKey(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  WorkoutSummary workout({
    required int calories,
    required int steps,
    required int durationSec,
    int hour = 12,
  }) {
    final start = DateTime(fixedNow.year, fixedNow.month, fixedNow.day, hour);
    final startUnix = start.millisecondsSinceEpoch ~/ 1000;
    return WorkoutSummary(
      number: 30,
      type: 6,
      startTime: startUnix,
      endTime: startUnix + durationSec,
      durationSec: durationSec,
      calories: calories,
      steps: steps,
    );
  }

  Future<HomeRepositoryImpl> buildRepo({
    List<WorkoutSummary> workouts = const [],
    FitnessTotalsDay? ftToday,
    bool ftLoadFailed = false,
    bool everSynced = true,
  }) async {
    final values = <String, Object>{
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.rememberedName: 'HUAWEI WATCH GT 5-A07',
      GateAPrefs.gateAPassed: true,
    };
    if (everSynced) {
      values[GateAPrefs.homeLastSyncStatus] = 'ok';
      values[GateAPrefs.homeLastSyncAtMs] = fixedNow.millisecondsSinceEpoch;
      values[GateAPrefs.lastSyncCursor] = 1;
    }
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    return HomeRepositoryImpl(
      prefs: prefs,
      link: _StubLink(),
      workouts: _Workouts(workouts),
      vitals: _Vitals(ftToday: ftToday, loadFailed: ftLoadFailed),
      now: () => fixedNow,
    );
  }

  test('FT today drives calories and steps; workout-sum drives workout time',
      () async {
    final today = dayKey(fixedNow);
    final repo = await buildRepo(
      workouts: [
        workout(calories: 349, steps: 0, durationSec: 3311),
      ],
      ftToday: FitnessTotalsDay(
        dayKey: today,
        dayStartUnix: 0,
        calories: 525,
        steps: 7825,
        exerciseDurationSec: 5064, // wire junk — must not drive Home minutes
      ),
    );
    final snap = await repo.loadSnapshot();
    expect(snap.caloriesLabel, '525');
    expect(snap.stepsLabel, '7,825');
    expect(snap.workoutTimeLabel, '55m · 1 session');
  });

  test('no FT falls back to workout-sum triple', () async {
    final repo = await buildRepo(
      workouts: [
        workout(calories: 340, steps: 100, durationSec: 3600, hour: 10),
        workout(calories: 441, steps: 200, durationSec: 3608, hour: 14),
      ],
    );
    final snap = await repo.loadSnapshot();
    expect(snap.caloriesLabel, '781');
    expect(snap.stepsLabel, '300');
    expect(snap.workoutTimeLabel, '2h · 2 sessions');
  });

  test('FT all-zero with no workouts shows zeros for cal/steps', () async {
    final today = dayKey(fixedNow);
    final repo = await buildRepo(
      ftToday: FitnessTotalsDay(
        dayKey: today,
        dayStartUnix: 0,
        calories: 0,
        steps: 0,
        exerciseDurationSec: 0,
      ),
    );
    final snap = await repo.loadSnapshot();
    expect(snap.caloriesLabel, '0');
    expect(snap.stepsLabel, '0');
    expect(snap.workoutTimeLabel, '0m · no sessions');
  });

  test('FT cal=0 with workout calories fails sanity → workout-sum triple',
      () async {
    final today = dayKey(fixedNow);
    final repo = await buildRepo(
      workouts: [
        workout(calories: 349, steps: 12, durationSec: 3311),
      ],
      ftToday: FitnessTotalsDay(
        dayKey: today,
        dayStartUnix: 0,
        calories: 0,
        steps: 0,
        exerciseDurationSec: 0,
      ),
    );
    final snap = await repo.loadSnapshot();
    expect(snap.caloriesLabel, '349');
    expect(snap.stepsLabel, '12');
    expect(snap.workoutTimeLabel, '55m · 1 session');
  });

  test('FT for yesterday only → today workout-sum', () async {
    final yesterday = dayKey(fixedNow.subtract(const Duration(days: 1)));
    final repo = await buildRepo(
      workouts: [
        workout(calories: 200, steps: 50, durationSec: 600),
      ],
      ftToday: FitnessTotalsDay(
        dayKey: yesterday,
        dayStartUnix: 0,
        calories: 999,
        steps: 9999,
        exerciseDurationSec: 0,
      ),
    );
    final snap = await repo.loadSnapshot();
    expect(snap.caloriesLabel, '200');
    expect(snap.stepsLabel, '50');
    expect(snap.workoutTimeLabel, '10m · 1 session');
  });

  test('fail-closed FT load → workout-sum', () async {
    final repo = await buildRepo(
      workouts: [
        workout(calories: 100, steps: 20, durationSec: 120),
      ],
      ftToday: FitnessTotalsDay(
        dayKey: dayKey(fixedNow),
        dayStartUnix: 0,
        calories: 525,
        steps: 7825,
        exerciseDurationSec: 0,
      ),
      ftLoadFailed: true,
    );
    final snap = await repo.loadSnapshot();
    expect(snap.caloriesLabel, '100');
    expect(snap.stepsLabel, '20');
    expect(snap.workoutTimeLabel, '2m · 1 session');
  });

  test('indoor run type 5 today appears as a session card, not swim-gated',
      () async {
    final start = DateTime(fixedNow.year, fixedNow.month, fixedNow.day, 10);
    final startUnix = start.millisecondsSinceEpoch ~/ 1000;
    final repo = await buildRepo(
      workouts: [
        WorkoutSummary(
          number: 35,
          type: 5,
          startTime: startUnix,
          endTime: startUnix + 433,
          durationSec: 433,
          distanceM: 1000,
          calories: 80,
          steps: 1200,
          load: 40,
          aerobicEffect: 23,
          recoveryTime: 600,
        ),
      ],
    );
    final snap = await repo.loadSnapshot();
    expect(snap.precedence, isNot(HomePrecedence.notPaired));
    expect(snap.todaySessions, hasLength(1));
    expect(snap.todaySessions.first.title, 'Indoor run · #35');
    expect(
      snap.todaySessions.first.meta
          .where((m) => m.label == 'TE')
          .map((m) => m.value),
      ['2.3'],
    );
    expect(snap.workoutTimeLabel, '7m · 1 session');
  });

  test('pool swim type 6 today is a session card with identity', () async {
    final start = DateTime(fixedNow.year, fixedNow.month, fixedNow.day, 7);
    final startUnix = start.millisecondsSinceEpoch ~/ 1000;
    final repo = await buildRepo(
      workouts: [
        WorkoutSummary(
          number: 33,
          type: 6,
          startTime: startUnix,
          endTime: startUnix + 3600,
          durationSec: 3600,
          distanceM: 1000,
          calories: 349,
          load: 100,
          aerobicEffect: 24,
          recoveryTime: 720,
        ),
      ],
    );
    final snap = await repo.loadSnapshot();
    expect(snap.todaySessions, hasLength(1));
    expect(snap.todaySessions.first.title, 'Pool swim · #33');
    expect(snap.todaySessions.first.workout.number, 33);
    expect(
      snap.todaySessions.first.meta.map((m) => m.label),
      containsAll(['Load', 'TE', 'Recovery']),
    );
  });

  test('non-today HR days do not surface as body HR', () async {
    final today = dayKey(fixedNow);
    final yesterday = dayKey(fixedNow.subtract(const Duration(days: 1)));
    SharedPreferences.setMockInitialValues({
      GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      GateAPrefs.rememberedName: 'GT5',
      GateAPrefs.gateAPassed: true,
      GateAPrefs.homeLastSyncStatus: 'ok',
      GateAPrefs.homeLastSyncAtMs: fixedNow.millisecondsSinceEpoch,
      GateAPrefs.lastSyncCursor: 1,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = HomeRepositoryImpl(
      prefs: prefs,
      link: _StubLink(),
      workouts: _Workouts(const []),
      vitals: _VitalsHr(
        days: [
          DailyHrDaySummary(
            dayKey: yesterday,
            minBpm: 40,
            avgBpm: 50,
            maxBpm: 60,
            sampleCount: 10,
          ),
        ],
        ftToday: FitnessTotalsDay(
          dayKey: today,
          dayStartUnix: 0,
          calories: 1,
          steps: 1,
          exerciseDurationSec: 0,
        ),
      ),
      now: () => fixedNow,
    );
    final snap = await repo.loadSnapshot();
    expect(snap.bodyHrLabel, isNull);
    expect(snap.bodyHrSparkSamples, isEmpty);
  });
}

class _VitalsHr extends _Vitals {
  _VitalsHr({required this.days, super.ftToday});

  final List<DailyHrDaySummary> days;

  @override
  Future<List<DailyHrDaySummary>> loadDailyHr() async => days;
}
