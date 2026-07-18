import 'dart:convert';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutHistoryRepositoryImpl implements WorkoutHistoryRepository {
  WorkoutHistoryRepositoryImpl({
    required HuaweiLink link,
    required SharedPreferences prefs,
  })  : _link = link,
        _prefs = prefs;

  final HuaweiLink _link;
  final SharedPreferences _prefs;

  /// Same empty-history floor as GB / native HuaweiWorkoutSync.
  static const fallbackStartUnix = 1654819200;

  @override
  Future<bool> isGateAPassed() async =>
      _prefs.getBool(GateAPrefs.gateAPassed) ?? false;

  @override
  Future<List<WorkoutSummary>> loadLocal() async {
    final raw = _prefs.getString(GateAPrefs.workoutsJson);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => WorkoutSummary.fromMap(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch() async {
    if (!await isGateAPassed()) {
      return const Left(
        ServerFailure('Gate A unlock required before Sync'),
      );
    }

    // Gate B testing: always request full history from the GB-style floor.
    // Incremental cursor sync can return later once AE6 is proven.
    final startUnix = fallbackStartUnix;
    final endUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final result = await _link.syncWorkouts(
      startUnix: startUnix,
      endUnix: endUnix,
    );

    switch (result.status) {
      case WorkoutSyncStatus.notReady:
        return Left(
          ServerFailure(result.message ?? 'Session not ready — reconnect'),
        );
      case WorkoutSyncStatus.stuck:
        return Left(
          ServerFailure(
            result.message ?? 'Sync stuck — disconnect and reconnect',
          ),
        );
      case WorkoutSyncStatus.error:
        return Left(ServerFailure(result.message ?? 'Sync failed'));
      case WorkoutSyncStatus.empty:
        // Keep prior rows; empty window is success.
        final local = await loadLocal();
        return Right(local);
      case WorkoutSyncStatus.ok:
        final merged = await _mergeAndPersist(result.workouts);
        return Right(merged);
    }
  }

  Future<List<WorkoutSummary>> _mergeAndPersist(
    List<WorkoutSummary> incoming,
  ) async {
    final existing = await loadLocal();
    final byNumber = <int, WorkoutSummary>{
      for (final w in existing) w.number: w,
    };
    for (final w in incoming) {
      byNumber[w.number] = w;
    }
    final merged = byNumber.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    await _prefs.setString(
      GateAPrefs.workoutsJson,
      jsonEncode(merged.map((w) => w.toJson()).toList()),
    );

    // Book-keeping only while Sync still uses the full-history window.
    var maxEnd = 0;
    for (final w in merged) {
      if (w.endTime > maxEnd) maxEnd = w.endTime;
    }
    if (maxEnd > 0) {
      await _prefs.setInt(GateAPrefs.lastSyncCursor, maxEnd + 1);
    }
    return merged;
  }
}
