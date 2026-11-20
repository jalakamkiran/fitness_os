import 'dart:async';

import 'package:fitness_os/core/backend/backend_sync_telemetry.dart';
import 'package:fitness_os/core/backend/backend_transport.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';

class FakeBackendTransport implements BackendTransport {
  final List<List<int>> capturedBodies = [];
  final List<Map<String, String>> capturedHeaders = [];
  final queue = <TransportResponse>[];
  final manifestQueue = <TransportResponse>[];

  Completer<void>? blockCompleter;

  @override
  Future<TransportResponse> postSync({
    required List<int> bodyBytes,
    required Map<String, String> headers,
  }) async {
    if (blockCompleter != null) {
      await blockCompleter!.future;
    }
    capturedBodies.add(bodyBytes);
    capturedHeaders.add(Map.from(headers));
    if (queue.isEmpty) {
      return const TransportResponse(status: 200, json: {'synced': 1});
    }
    return queue.removeAt(0);
  }

  @override
  Future<TransportResponse> getManifest({required String fromDay}) async {
    if (manifestQueue.isEmpty) {
      return const TransportResponse(status: 404);
    }
    return manifestQueue.removeAt(0);
  }
}

class RecordingTelemetry implements BackendSyncTelemetry {
  final List<(String, Map<String, Object?>)> breadcrumbs = [];

  @override
  Future<void> breadcrumb(String stage,
          {Map<String, Object?> data = const {}}) async =>
      breadcrumbs.add((stage, data));

  @override
  Future<void> ledgerReset(String reason) async =>
      breadcrumbs.add(('reconcile', {'reason': reason}));
}

class FakeWorkoutRepo implements WorkoutHistoryRepository {
  FakeWorkoutRepo({this.workouts = const [], this.busy = false});

  List<WorkoutSummary> workouts;
  bool busy;

  @override
  bool get isSyncOrMergeInFlight => busy;

  @override
  Future<List<WorkoutSummary>> loadLocal() async => workouts;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVitalsRepo implements VitalsRepository {
  FakeVitalsRepo({this.busy = false});

  bool busy;
  List<SleepSessionSummary> sleep = const [];
  List<FitnessTotalsDay> totals = const [];
  List<DailyHrDaySummary> dailyHr = const [];

  @override
  bool get isSyncOrMergeInFlight => busy;

  @override
  Future<List<SleepSessionSummary>> loadSleepSessions() async => sleep;

  @override
  Future<List<SleepStageSummary>> loadSleepStages(SleepSessionSummary session) async => [];

  @override
  Future<TruSleepSequenceSession?> loadTruSleepSummary(SleepSessionSummary session) async =>
      null;

  @override
  Future<List<FitnessTotalsDay>> loadFitnessTotals() async => totals;

  @override
  Future<List<DailyHrDaySummary>> loadDailyHr() async => dailyHr;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}