import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/fos_huawei_log.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/canonical_swim_store.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/swim_style_capability_log.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutHistoryRepositoryImpl implements WorkoutHistoryRepository {
  WorkoutHistoryRepositoryImpl({
    required HuaweiLink link,
    required SharedPreferences prefs,
    CanonicalSwimStore? swimStore,
    Directory? Function()? swimRootOverride,
    void Function()? onSyncSettled,
  })  : _link = link,
        _prefs = prefs,
        _swimStore = swimStore ??
            CanonicalSwimStore(rootOverride: swimRootOverride),
        _onSyncSettled = onSyncSettled;

  final HuaweiLink _link;
  final SharedPreferences _prefs;
  final CanonicalSwimStore _swimStore;
  final void Function()? _onSyncSettled;

  /// Same empty-history floor as GB / native HuaweiWorkoutSync.
  static const fallbackStartUnix = 1654819200;

  /// Overlap when advancing from [GateAPrefs.lastSyncCursor] so boundary
  /// workouts are not missed if the watch clocks slightly disagree.
  static const cursorOverlapSec = 86400;

  /// v2: swim/pace page index TLV 0x08 + GB 0x83 field map (strokes/time).
  /// Pref below this → next Sync uses [fallbackStartUnix] once, then stamps.
  /// (v3 one-shot force for stroke-style capability proof is complete — left at v2.)
  static const currentSwimSegmentParserVersion = 2;

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
  Future<CanonicalSwimSession?> loadCanonicalSwim(int workoutNumber) =>
      _swimStore.load(workoutNumber);

  @override
  CanonicalSwimSession? canonicalSwimFromSummary(WorkoutSummary workout) =>
      CanonicalSwimSession.fromWorkoutSummary(workout);

  @override
  Future<List<CanonicalSwimSession>> loadAllCanonicalSwims() async {
    final fromFiles = await _swimStore.loadAll();
    final byNumber = <int, CanonicalSwimSession>{
      for (final s in fromFiles) s.workoutNumber: s,
    };
    // Rebuild from local summaries when side-file missing (pre-W1 syncs).
    for (final w in await loadLocal()) {
      if (byNumber.containsKey(w.number)) continue;
      final built = CanonicalSwimSession.fromWorkoutSummary(w);
      if (built != null) byNumber[w.number] = built;
    }
    return byNumber.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  @override
  Future<SwimDiagnosisReport> loadSwimDiagnosisReport({
    int? focusWorkoutNumber,
  }) async {
    final sessions = await loadAllCanonicalSwims();
    return diagnoseSwimSessions(
      sessions,
      focusWorkoutNumber: focusWorkoutNumber,
    );
  }

  @override
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch() async {
    if (!await isGateAPassed()) {
      return const Left(
        ServerFailure('Gate A unlock required before Sync'),
      );
    }

    final endUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final startUnix = await _resolveSyncStartUnix(endUnix);

    try {
      final result = await _link.syncWorkouts(
        startUnix: startUnix,
        endUnix: endUnix,
      );

      switch (result.status) {
        case WorkoutSyncStatus.notReady:
        case WorkoutSyncStatus.busy:
        case WorkoutSyncStatus.stuck:
        case WorkoutSyncStatus.partialBatch:
        case WorkoutSyncStatus.error:
          // Soft Sync failure — not a capability Pass or Blocked-empty claim.
          FosHuaweiLog.i(
            syncNotOkSwimStyleOutcomeLine(result.status),
            op: 'sync',
          );
          return Left(
            ServerFailure(
              result.message ??
                  switch (result.status) {
                    WorkoutSyncStatus.notReady =>
                      'Session not ready — reconnect',
                    WorkoutSyncStatus.busy =>
                      'Another Sync is already in progress',
                    WorkoutSyncStatus.stuck =>
                      'Sync stuck — disconnect and reconnect',
                    WorkoutSyncStatus.partialBatch =>
                      'Workout Sync incomplete — retry after reconnect',
                    _ => 'Sync failed',
                  },
            ),
          );
        case WorkoutSyncStatus.empty:
          // Keep prior rows; empty window is success.
          final local = await loadLocal();
          return Right(local);
        case WorkoutSyncStatus.ok:
          final merged = await _mergeAndPersist(result.workouts);
          emitSwimStyleCapabilityLogs(
            result.workouts,
            log: (message) => FosHuaweiLog.i(message, op: 'sync'),
          );
          await _prefs.setInt(
            GateAPrefs.swimSegmentParserVersion,
            currentSwimSegmentParserVersion,
          );
          return Right(merged);
      }
    } finally {
      _onSyncSettled?.call();
    }
  }

  /// Incremental when cursor exists and no local row is still partial;
  /// otherwise full-history from [fallbackStartUnix] (plan invariant).
  /// Also full-history once after [currentSwimSegmentParserVersion] bumps.
  Future<int> _resolveSyncStartUnix(int endUnix) async {
    final parserVer =
        _prefs.getInt(GateAPrefs.swimSegmentParserVersion) ?? 0;
    if (parserVer < currentSwimSegmentParserVersion) {
      return fallbackStartUnix;
    }
    final cursor = _prefs.getInt(GateAPrefs.lastSyncCursor);
    final local = await loadLocal();
    final hasPartial =
        local.any((w) => w.enrichmentStatus == 'partial');
    if (cursor == null || cursor <= 0 || hasPartial) {
      return fallbackStartUnix;
    }
    final withOverlap = cursor - cursorOverlapSec;
    if (withOverlap < fallbackStartUnix) return fallbackStartUnix;
    if (withOverlap > endUnix) return endUnix;
    return withOverlap;
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

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final swimSessions = <CanonicalSwimSession>[];
    for (final w in incoming) {
      final session = CanonicalSwimSession.fromWorkoutSummary(
        w,
        builtAtUnix: now,
      );
      if (session != null) swimSessions.add(session);
    }
    if (swimSessions.isNotEmpty) {
      await _swimStore.saveAll(swimSessions);
    }

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
