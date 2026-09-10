import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/fos_huawei_log.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/canonical_swim_store.dart';
import 'package:fitness_os/features/workout_history/data/workout_leftover_store.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/swim_style_capability_log.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutHistoryRepositoryImpl implements WorkoutHistoryRepository {
  WorkoutHistoryRepositoryImpl({
    required HuaweiLink link,
    required SharedPreferences prefs,
    CanonicalSwimStore? swimStore,
    WorkoutLeftoverStore? leftoverStore,
    Directory? Function()? swimRootOverride,
    Directory? Function()? leftoverRootOverride,
    Directory? Function()? sideFileRootOverride,
    void Function()? onSyncSettled,
  })  : _link = link,
        _prefs = prefs,
        _swimStore = swimStore ??
            CanonicalSwimStore(rootOverride: swimRootOverride),
        _leftoverStore = leftoverStore ??
            WorkoutLeftoverStore(rootOverride: leftoverRootOverride),
        _sideFileRootOverride = sideFileRootOverride,
        _onSyncSettled = onSyncSettled;

  final HuaweiLink _link;
  final SharedPreferences _prefs;
  final CanonicalSwimStore _swimStore;
  final WorkoutLeftoverStore _leftoverStore;
  final Directory? Function()? _sideFileRootOverride;
  final void Function()? _onSyncSettled;

  bool _mergeInFlight = false;
  bool _lastLeftoverPersistLanded = true;

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
  bool get isSyncOrMergeInFlight => _link.syncInFlight || _mergeInFlight;

  @override
  bool get lastLeftoverPersistLanded => _lastLeftoverPersistLanded;

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
  Future<void> clearLocal() async {
    await _leftoverStore.clearLocal();
    await _wipeSampleDir();
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
    _mergeInFlight = true;
    _lastLeftoverPersistLanded = true;
    try {
      final prepared = <WorkoutSummary>[];
      for (final w in incoming) {
        prepared.add(await _persistSideArtifacts(w));
      }

      final existing = await loadLocal();
      final byNumber = <int, WorkoutSummary>{
        for (final w in existing) w.number: w,
      };
      for (final w in prepared) {
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
      for (final w in prepared) {
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
    } finally {
      _mergeInFlight = false;
    }
  }

  /// Write leftover bytes to side-file; attach relative sample path; strip bodies.
  Future<WorkoutSummary> _persistSideArtifacts(WorkoutSummary w) async {
    final samplePath = w.samplePath; // already relative via fromMap
    var leftoverPath = w.leftoverPath;
    var leftoverLen = w.leftoverLen;
    var leftoverPresent = w.leftoverPresent;
    final bytes = w.leftoverBytes;

    if (bytes != null && bytes.isNotEmpty) {
      leftoverLen = bytes.length;
      try {
        leftoverPath = await _leftoverStore.save(
          workoutNumber: w.number,
          startTime: w.startTime,
          bytes: bytes,
        );
        leftoverPresent = true;
        FosHuaweiLog.i(
          'workout leftover number=${w.number} start=${w.startTime} '
          'len=${bytes.length} path=$leftoverPath',
          op: 'sync',
        );
      } catch (e) {
        _lastLeftoverPersistLanded = false;
        leftoverPath = null;
        leftoverPresent = false;
        FosHuaweiLog.w(
          'workout leftover write failed number=${w.number} '
          'len=${bytes.length} | $e',
          op: 'sync',
        );
      }
    } else {
      // Empty leftover (all TLVs named / none unmatched) is a valid landed outcome.
      leftoverPresent ??= false;
      if (leftoverLen == null || leftoverLen == 0) {
        leftoverPath = null;
      }
    }

    if (samplePath != null) {
      FosHuaweiLog.i(
        'workout sample ref number=${w.number} path=$samplePath '
        'sampleFetch=${w.sampleFetch ?? '—'} '
        'sampleCount=${w.sampleCount ?? 0}',
        op: 'sync',
      );
    }

    return w.copyWith(
      leftoverLen: leftoverLen,
      leftoverPresent: leftoverPresent,
      leftoverPath: leftoverPath,
      clearLeftoverPath: leftoverPath == null,
      clearLeftoverBytes: true,
      samplePath: samplePath,
    );
  }

  Future<void> _wipeSampleDir() async {
    final root = await _sideFileRoot();
    if (root == null) return;
    final dir = Directory('${root.path}/${GateAPrefs.workoutHrSamplesDir}');
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort wipe.
    }
  }

  Future<Directory?> _sideFileRoot() async {
    final override = _sideFileRootOverride?.call();
    if (override != null) return override;
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }
}
