import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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

  /// Leftover-keep impl version. Mismatch forces one Count window from the
  /// native 2022 floor; stamped only after leftover persist lands on ok /
  /// partial_batch (not Totals-prefix stuck).
  static const currentLeftoverKeepImplVersion = 1;

  /// Matches native [HuaweiWorkoutSync.FALLBACK_START_UNIX] (2022-06-10).
  static const leftoverKeepFullHistoryStartUnix = 1654819200;

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
    // Clock 3 / cursor delta — also the enrich floor during leftover-keep one-shot.
    final enrichStartUnix = await _resolveSyncStartUnix(endUnix);
    final storedLeftoverKeep =
        _prefs.getInt(GateAPrefs.leftoverKeepImplVersion) ?? 0;
    final forceFullHistory =
        storedLeftoverKeep < currentLeftoverKeepImplVersion;
    // Clock 1: stale leftover-keep → Count from 2022 floor; enrich stays delta.
    final startUnix =
        forceFullHistory ? leftoverKeepFullHistoryStartUnix : enrichStartUnix;

    try {
      final result = await _link.syncWorkouts(
        startUnix: startUnix,
        endUnix: endUnix,
        enrichStartUnix: enrichStartUnix,
      );

      switch (result.status) {
        case WorkoutSyncStatus.notReady:
        case WorkoutSyncStatus.busy:
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
                    _ => 'Sync failed',
                  },
            ),
          );
        case WorkoutSyncStatus.stuck:
          // Totals-prefix stuck: persist maps that arrived (AE6/R5). Empty
          // stuck stays blocked (AE7) — do not merge or advance cursor.
          // Do not stamp leftover-keep (next Count stays 2022 floor).
          FosHuaweiLog.i(
            syncNotOkSwimStyleOutcomeLine(result.status),
            op: 'sync',
          );
          if (result.workouts.isEmpty) {
            return Left(
              ServerFailure(
                result.message ?? 'Sync stuck — disconnect and reconnect',
              ),
            );
          }
          if (!_gateStillPassed()) {
            return const Left(ServerFailure('Gate cleared — sync discarded'));
          }
          final stuckMerged = await _mergeAndPersist(
            result.workouts,
            advanceCursor: false,
          );
          emitSwimStyleCapabilityLogs(
            result.workouts,
            log: (message) => FosHuaweiLog.i(message, op: 'sync'),
          );
          return Right(stuckMerged);
        case WorkoutSyncStatus.partialBatch:
          // Sample enrich incomplete but Totals landed — commit maps (R5/AE6).
          FosHuaweiLog.i(
            syncNotOkSwimStyleOutcomeLine(result.status),
            op: 'sync',
          );
          if (result.workouts.isEmpty) {
            final local = await loadLocal();
            return Right(local);
          }
          if (!_gateStillPassed()) {
            return const Left(ServerFailure('Gate cleared — sync discarded'));
          }
          final partialMerged = await _mergeAndPersist(
            result.workouts,
            advanceCursor: true,
          );
          emitSwimStyleCapabilityLogs(
            result.workouts,
            log: (message) => FosHuaweiLog.i(message, op: 'sync'),
          );
          await _maybeStampLeftoverKeepVersion();
          return Right(partialMerged);
        case WorkoutSyncStatus.empty:
          // Keep prior rows; empty window is success. Do not stamp-on-empty.
          final local = await loadLocal();
          return Right(local);
        case WorkoutSyncStatus.ok:
          if (!_gateStillPassed()) {
            return const Left(ServerFailure('Gate cleared — sync discarded'));
          }
          final merged = await _mergeAndPersist(result.workouts);
          emitSwimStyleCapabilityLogs(
            result.workouts,
            log: (message) => FosHuaweiLog.i(message, op: 'sync'),
          );
          await _prefs.setInt(
            GateAPrefs.swimSegmentParserVersion,
            currentSwimSegmentParserVersion,
          );
          await _maybeStampLeftoverKeepVersion();
          return Right(merged);
      }
    } finally {
      _onSyncSettled?.call();
    }
  }

  /// Stamp leftover-keep only after leftover persist was attempted for every
  /// workout in the native list and [lastLeftoverPersistLanded] is true.
  Future<void> _maybeStampLeftoverKeepVersion() async {
    if (!_lastLeftoverPersistLanded || !_gateStillPassed()) return;
    await _prefs.setInt(
      GateAPrefs.leftoverKeepImplVersion,
      currentLeftoverKeepImplVersion,
    );
  }

  /// Late merge after Forget / Gate A clear is a no-op (identity wiped).
  bool _gateStillPassed() => _prefs.getBool(GateAPrefs.gateAPassed) ?? false;

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
    List<WorkoutSummary> incoming, {
    bool advanceCursor = true,
  }) async {
    _mergeInFlight = true;
    _lastLeftoverPersistLanded = true;
    try {
      // Forget may clear Gate A while native Sync was still in flight.
      if (!_gateStillPassed()) {
        _lastLeftoverPersistLanded = false;
        return const [];
      }

      final existing = await loadLocal();
      final byNumber = <int, WorkoutSummary>{
        for (final w in existing) w.number: w,
      };

      final prepared = <WorkoutSummary>[];
      for (final w in incoming) {
        if (!_gateStillPassed()) {
          _lastLeftoverPersistLanded = false;
          return const [];
        }
        final prior = byNumber[w.number];
        // Do not let totals-only rows carry enrichmentStatus=partial — that
        // widens _resolveSyncStartUnix (clock 3) and can reopen 2022.
        final united = _unionWorkout(prior, _sanitizeEnrichmentStatus(w));
        prepared.add(await _persistSideArtifacts(united));
      }

      for (final w in prepared) {
        byNumber[w.number] = w;
      }
      final merged = byNumber.values.toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));

      if (!_gateStillPassed()) {
        _lastLeftoverPersistLanded = false;
        return const [];
      }

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
        if (session == null) continue;
        final priorSwim = await _swimStore.load(session.workoutNumber);
        if (priorSwim != null &&
            priorSwim.startTime == session.startTime &&
            _swimIncomingThinner(session, priorSwim)) {
          // Totals-only re-pull must not empty richer lap files.
          continue;
        }
        swimSessions.add(session);
      }
      if (swimSessions.isNotEmpty) {
        await _swimStore.saveAll(swimSessions);
      }

      // Totals-prefix stuck must not advance past unfetched Count numbers.
      if (advanceCursor) {
        var maxEnd = 0;
        for (final w in merged) {
          if (w.endTime > maxEnd) maxEnd = w.endTime;
        }
        if (maxEnd > 0) {
          await _prefs.setInt(GateAPrefs.lastSyncCursor, maxEnd + 1);
        }
      }
      return merged;
    } finally {
      _mergeInFlight = false;
    }
  }

  /// Keep [enrichmentStatus]=partial only when sample (or other hint-gated)
  /// enrich is incomplete. Totals-only rows must stay non-partial so clock 3
  /// does not widen the next Count window to historical starts.
  WorkoutSummary _sanitizeEnrichmentStatus(WorkoutSummary w) {
    if (w.enrichmentStatus != 'partial') return w;
    final totalsOnly = (w.dataCount ?? 0) == 0 &&
        (w.paceCount ?? 0) == 0 &&
        (w.segmentsCount ?? 0) == 0;
    if (!totalsOnly) return w;
    return w.copyWith(enrichmentStatus: 'none');
  }

  /// Presence-preserving union for the same workout number.
  ///
  /// Same [startTime]: keep present leftover / sample refs when incoming is
  /// empty or header-only; named scalars use null ≠ 0 (absent leaves prior).
  /// Different [startTime]: treat as a new session — take incoming as-is.
  WorkoutSummary _unionWorkout(WorkoutSummary? local, WorkoutSummary incoming) {
    if (local == null || local.startTime != incoming.startTime) {
      return incoming;
    }

    final leftover = _unionLeftover(local, incoming);
    final sample = _unionSampleRefs(local, incoming);
    final segments = _unionSegments(local, incoming);

    return WorkoutSummary(
      number: incoming.number,
      startTime: incoming.startTime,
      endTime: incoming.endTime,
      durationSec: incoming.durationSec,
      type: incoming.type,
      calories: incoming.calories ?? local.calories,
      distanceM: incoming.distanceM ?? local.distanceM,
      steps: incoming.steps ?? local.steps,
      dataCount: incoming.dataCount ?? local.dataCount,
      paceCount: incoming.paceCount ?? local.paceCount,
      segmentsCount: segments != null
          ? (incoming.segmentsCount ??
              local.segmentsCount ??
              segments.length)
          : (incoming.segmentsCount ?? local.segmentsCount),
      sampleCount: sample.sampleCount,
      enrichmentStatus: incoming.enrichmentStatus ?? local.enrichmentStatus,
      hrMin: incoming.hrMin ?? local.hrMin,
      hrMax: incoming.hrMax ?? local.hrMax,
      hrPeak: incoming.hrPeak ?? local.hrPeak,
      swimType: incoming.swimType ?? local.swimType,
      strokes: incoming.strokes ?? local.strokes,
      strokeRate: incoming.strokeRate ?? local.strokeRate,
      avgSwolf: incoming.avgSwolf ?? local.avgSwolf,
      sessionFlag: incoming.sessionFlag ?? local.sessionFlag,
      poolLength: incoming.poolLength ?? local.poolLength,
      laps: incoming.laps ?? local.laps,
      load: incoming.load ?? local.load,
      aerobicEffect: incoming.aerobicEffect ?? local.aerobicEffect,
      anaerobicEffect: incoming.anaerobicEffect ?? local.anaerobicEffect,
      recoveryTime: incoming.recoveryTime ?? local.recoveryTime,
      trainingPoints: incoming.trainingPoints ?? local.trainingPoints,
      leftoverLen: leftover.leftoverLen,
      leftoverPresent: leftover.leftoverPresent,
      leftoverPath: leftover.leftoverPath,
      leftoverBytes: leftover.leftoverBytes,
      samplePath: sample.samplePath,
      sampleFetch: sample.sampleFetch,
      enrichmentTags: (incoming.enrichmentTags != null &&
              incoming.enrichmentTags!.isNotEmpty)
          ? incoming.enrichmentTags
          : local.enrichmentTags,
      segments: segments,
    );
  }

  /// Leftover: keep present local when incoming empty; take incoming when local
  /// empty; if both have bodies, keep local (do not compare lengths).
  ({
    int? leftoverLen,
    bool? leftoverPresent,
    String? leftoverPath,
    Uint8List? leftoverBytes,
  }) _unionLeftover(WorkoutSummary local, WorkoutSummary incoming) {
    final incomingHasBody =
        incoming.leftoverBytes != null && incoming.leftoverBytes!.isNotEmpty;
    final localHasPresent = local.leftoverPresent == true ||
        (local.leftoverPath != null && local.leftoverPath!.isNotEmpty) ||
        (local.leftoverLen != null && local.leftoverLen! > 0);

    if (incomingHasBody && !localHasPresent) {
      return (
        leftoverLen: incoming.leftoverLen ?? incoming.leftoverBytes!.length,
        leftoverPresent: true,
        leftoverPath: incoming.leftoverPath,
        leftoverBytes: incoming.leftoverBytes,
      );
    }
    if (localHasPresent) {
      // Keep local — including when both have bodies.
      return (
        leftoverLen: local.leftoverLen,
        leftoverPresent: local.leftoverPresent ?? true,
        leftoverPath: local.leftoverPath,
        leftoverBytes: null, // already on disk; do not re-write / clobber
      );
    }
    // Neither present: adopt incoming index (may be explicit empty).
    return (
      leftoverLen: incoming.leftoverLen,
      leftoverPresent: incoming.leftoverPresent,
      leftoverPath: incoming.leftoverPath,
      leftoverBytes: incoming.leftoverBytes,
    );
  }

  /// HR sample refs: keep when incoming is header-only; replace only when
  /// incoming has a more complete series (higher sampleCount / new path).
  ({
    String? samplePath,
    int? sampleCount,
    String? sampleFetch,
  }) _unionSampleRefs(WorkoutSummary local, WorkoutSummary incoming) {
    final localCount = local.sampleCount ?? 0;
    final incomingCount = incoming.sampleCount ?? 0;
    final localHasPath =
        local.samplePath != null && local.samplePath!.isNotEmpty;
    final incomingHasPath =
        incoming.samplePath != null && incoming.samplePath!.isNotEmpty;

    // Header-only Data: no path and no positive point count.
    if (!incomingHasPath && incomingCount <= 0) {
      return (
        samplePath: local.samplePath,
        sampleCount: local.sampleCount,
        sampleFetch: local.sampleFetch,
      );
    }

    final incomingRicher =
        incomingCount > localCount || (incomingHasPath && !localHasPath);
    if (incomingRicher) {
      return (
        samplePath: incoming.samplePath,
        sampleCount: incoming.sampleCount,
        sampleFetch: incoming.sampleFetch,
      );
    }

    return (
      samplePath: local.samplePath,
      sampleCount: local.sampleCount,
      sampleFetch: local.sampleFetch,
    );
  }

  List<WorkoutSegment>? _unionSegments(
    WorkoutSummary local,
    WorkoutSummary incoming,
  ) {
    final incomingSegs = incoming.segments;
    final localSegs = local.segments;
    final incomingHas =
        incomingSegs != null && incomingSegs.isNotEmpty;
    final localHas = localSegs != null && localSegs.isNotEmpty;
    if (incomingHas) return incomingSegs;
    if (localHas) return localSegs;
    return incomingSegs ?? localSegs;
  }

  /// Incoming swim JSON is thinner when it lacks lap/segment rows the local
  /// file already has (Totals-only re-pull).
  bool _swimIncomingThinner(
    CanonicalSwimSession incoming,
    CanonicalSwimSession local,
  ) {
    final localLaps = local.p0.laps.length;
    final incomingLaps = incoming.p0.laps.length;
    return localLaps > incomingLaps;
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
