import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/fos_huawei_log.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/canonical_swim_store.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
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
    RunSessionStore? runSessionStore,
    Directory? Function()? runSessionRootOverride,
    void Function()? onSyncSettled,
  })  : _link = link,
        _prefs = prefs,
        _swimStore = swimStore ??
            CanonicalSwimStore(rootOverride: swimRootOverride),
        _runSessionStore = runSessionStore ??
            RunSessionStore(rootOverride: runSessionRootOverride),
        _onSyncSettled = onSyncSettled;

  final HuaweiLink _link;
  final SharedPreferences _prefs;
  final CanonicalSwimStore _swimStore;
  final RunSessionStore _runSessionStore;
  final void Function()? _onSyncSettled;

  /// Overlap when advancing from [GateAPrefs.lastSyncCursor] so boundary
  /// workouts are not missed if the watch clocks slightly disagree.
  static const cursorOverlapSec = 86400;

  /// Cold-start / no-cursor window — same span as activity Sync, not full history.
  static const coldStartWindowDays = HuaweiLink.activityWindowDays;

  /// v2: swim/pace page index TLV 0x08 + GB 0x83 field map (strokes/time).
  /// Stamped after a successful Sync; does **not** force a full-history pull.
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
          final stamped = await _persistPeeledSideFiles(
            result.peeled,
            result.workouts,
          );
          final merged = await _mergeAndPersist(stamped);
          emitSwimStyleCapabilityLogs(
            stamped,
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

  /// Write peeled leftover/sample/pace bodies via [RunSessionStore].
  ///
  /// Side-file write failure → stamp [WorkoutStreamHonesty.incomplete] on the
  /// affected streams; Totals scalars remain mergeable (U3 soft-incomplete).
  /// Never logs body payloads — workout # / lengths only.
  Future<List<WorkoutSummary>> _persistPeeledSideFiles(
    List<PeeledWorkoutPayload>? peeled,
    List<WorkoutSummary> workouts,
  ) async {
    if (peeled == null || peeled.isEmpty) return workouts;
    final byNumber = <int, WorkoutSummary>{
      for (final w in workouts) w.number: w,
    };
    for (final payload in peeled) {
      if (!payload.hasBodiesToPersist) continue;
      try {
        await _runSessionStore.save(payload);
        FosHuaweiLog.i(
          'run-session side-files saved workout=#${payload.workoutNumber} '
          'leftovers=${payload.totalsLeftovers.length} '
          'dataPages=${payload.dataPages.length} '
          'paceBlocks=${payload.paceBlocks.length}',
          op: 'sync',
        );
      } catch (e) {
        FosHuaweiLog.w(
          'run-session side-file write failed workout=#${payload.workoutNumber}',
          op: 'sync',
        );
        final existing = byNumber[payload.workoutNumber];
        if (existing == null) continue;
        byNumber[payload.workoutNumber] = existing.copyWith(
          leftoversStatus: payload.totalsLeftovers.isNotEmpty
              ? WorkoutStreamHonesty.incomplete
              : existing.leftoversStatus,
          dataPagesStatus: payload.dataPages.isNotEmpty
              ? WorkoutStreamHonesty.incomplete
              : existing.dataPagesStatus,
          paceBlocksStatus: payload.paceBlocks.isNotEmpty
              ? WorkoutStreamHonesty.incomplete
              : existing.paceBlocksStatus,
        );
      }
    }
    return workouts.map((w) => byNumber[w.number] ?? w).toList();
  }

  /// Delta-only Count window: cursor − overlap when present; otherwise last
  /// [coldStartWindowDays]. Partials extend the window back to the earliest
  /// partial start (still not a 2022 full-history dump).
  Future<int> _resolveSyncStartUnix(int endUnix) async {
    final coldStart = endUnix - coldStartWindowDays * 86400;
    final cursor = _prefs.getInt(GateAPrefs.lastSyncCursor);
    var start = (cursor == null || cursor <= 0)
        ? coldStart
        : cursor - cursorOverlapSec;

    final local = await loadLocal();
    for (final w in local) {
      if (w.enrichmentStatus == 'partial') {
        start = math.min(start, w.startTime - cursorOverlapSec);
      }
    }

    if (start > endUnix) return endUnix;
    return start;
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
