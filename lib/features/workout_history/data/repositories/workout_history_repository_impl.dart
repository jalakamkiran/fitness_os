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

  /// Run/session leftover + stream remap generation (monotonic escape hatch).
  ///
  /// v2: one-shot 14-day wide Count (ignore cursor).
  /// v3: one-shot **full-history** Count from mid-2022 FALLBACK — needed when
  /// the watch still holds Outdoor Runs older than the incremental cursor
  /// (Sep 9 missed after cursor advanced to Sep 10+). Still hint-gated
  /// Data/Pace (no force-empty enrichment).
  static const currentRunSessionParserVersion = 3;

  /// Same floor GB / POC used for first full-history Count testing.
  static const fullHistoryStartUnix = 1_654_819_200; // 2022-06-10

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
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch({
    bool forceFullHistory = false,
  }) async {
    if (!await isGateAPassed()) {
      return const Left(
        ServerFailure('Gate A unlock required before Sync'),
      );
    }

    final endUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final storedRunParser =
        _prefs.getInt(GateAPrefs.runSessionParserVersion) ?? 0;
    final parserForceFull =
        storedRunParser < currentRunSessionParserVersion;
    final useFullHistory = forceFullHistory || parserForceFull;
    // v2 cold-start only when explicitly between versions that used 14d —
    // v3+ always prefers full-history for parser bumps.
    final forceWide14d = false;
    final startUnix = await _resolveSyncStartUnix(
      endUnix,
      forceFullHistory: useFullHistory,
      forceWide14d: forceWide14d,
    );
    final windowLabel = useFullHistory
        ? 'full-history'
        : forceWide14d
            ? 'force-wide-14d'
            : 'delta';
    FosHuaweiLog.i(
      'workout Sync $windowLabel window=[$startUnix,$endUnix] '
      '(${_fmtUnix(startUnix)} → ${_fmtUnix(endUnix)}) '
      'runSessionParser=$storedRunParser→$currentRunSessionParserVersion '
      'forceFullHistory=$forceFullHistory',
      op: 'sync',
    );

    try {
      final result = await _link.syncWorkouts(
        startUnix: startUnix,
        endUnix: endUnix,
      );

      final softIncomplete = result.status == WorkoutSyncStatus.partialBatch ||
          result.status == WorkoutSyncStatus.stuck;
      final hasWorkouts = result.workouts.isNotEmpty;

      switch (result.status) {
        case WorkoutSyncStatus.notReady:
        case WorkoutSyncStatus.busy:
        case WorkoutSyncStatus.error:
          return _leftSoftFail(result);
        case WorkoutSyncStatus.stuck:
        case WorkoutSyncStatus.partialBatch:
          // Soft-incomplete with usable Totals → merge (AE6). Empty → Left
          // (AE7 blocked honesty — no tile-absence claim).
          if (!hasWorkouts) return _leftSoftFail(result);
          break;
        case WorkoutSyncStatus.empty:
          // Keep prior rows; empty window is success. Consume one-shot force
          // so we do not wide-pull forever when the watch has nothing new.
          if (useFullHistory || forceWide14d) {
            await _prefs.setInt(
              GateAPrefs.runSessionParserVersion,
              currentRunSessionParserVersion,
            );
          }
          FosHuaweiLog.i(
            'workout Sync empty Count ($windowLabel) — '
            'watch may omit already-synced sessions',
            op: 'sync',
          );
          final local = await loadLocal();
          return Right(local);
        case WorkoutSyncStatus.ok:
          break;
      }

      final peeled = await _persistPeeledSideFiles(
        result.peeled,
        result.workouts,
        softIncomplete: softIncomplete,
      );
      final stamped = <WorkoutSummary>[];
      for (final w in peeled) {
        final reconciled = await _reconcileRefsAndFiles(w);
        stamped.add(
          reconciled.copyWith(
            enrichmentStatus: WorkoutEnrichmentMerge.sessionEnrichmentStatus(
              softIncomplete: softIncomplete,
              workout: reconciled,
            ),
            parserGeneration: currentRunSessionParserVersion,
          ),
        );
      }
      final merged = await _mergeAndPersist(stamped);
      emitSwimStyleCapabilityLogs(
        stamped,
        log: (message) => FosHuaweiLog.i(message, op: 'sync'),
      );
      if (!softIncomplete) {
        await _prefs.setInt(
          GateAPrefs.swimSegmentParserVersion,
          currentSwimSegmentParserVersion,
        );
      }
      await _prefs.setInt(
        GateAPrefs.runSessionParserVersion,
        currentRunSessionParserVersion,
      );
      return Right(merged);
    } finally {
      _onSyncSettled?.call();
    }
  }

  Left<Failure, List<WorkoutSummary>> _leftSoftFail(WorkoutSyncResult result) {
    // Soft Sync failure — not a capability Pass or Blocked-empty claim.
    FosHuaweiLog.i(
      syncNotOkSwimStyleOutcomeLine(result.status),
      op: 'sync',
    );
    return Left(
      ServerFailure(
        result.message ??
            switch (result.status) {
              WorkoutSyncStatus.notReady => 'Session not ready — reconnect',
              WorkoutSyncStatus.busy => 'Another Sync is already in progress',
              WorkoutSyncStatus.stuck => 'Sync stuck — disconnect and reconnect',
              WorkoutSyncStatus.partialBatch =>
                'Workout Sync incomplete — retry after reconnect',
              _ => 'Sync failed',
            },
      ),
    );
  }

  /// Downgrade [WorkoutStreamHonesty.present] when side-files disagree with
  /// prefs refs — never stamp session `ok` unless refs+files agree.
  Future<WorkoutSummary> _reconcileRefsAndFiles(WorkoutSummary w) async {
    final checkLeftovers = w.leftoversStatus == WorkoutStreamHonesty.present;
    final checkData = w.dataPagesStatus == WorkoutStreamHonesty.present ||
        w.dataPagesStatus == WorkoutStreamHonesty.partial;
    final checkPace = w.paceBlocksStatus == WorkoutStreamHonesty.present ||
        w.paceBlocksStatus == WorkoutStreamHonesty.partial;
    if (!checkLeftovers && !checkData && !checkPace) return w;

    var leftoversStatus = w.leftoversStatus;
    var dataPagesStatus = w.dataPagesStatus;
    var paceBlocksStatus = w.paceBlocksStatus;
    var leftoverRefs = w.leftoverRefs;
    var dataPagesStored = w.dataPagesStored;
    var paceBlocksStored = w.paceBlocksStored;

    if (checkLeftovers) {
      final bodies = await _runSessionStore.loadTotalsLeftovers(w.number);
      if (bodies.isEmpty) {
        leftoversStatus = WorkoutStreamHonesty.incomplete;
      } else {
        leftoverRefs = bodies
            .map((b) => EnrichmentTagRef(id: b.id, len: b.len))
            .toList();
      }
    }
    if (checkData) {
      final pages = await _runSessionStore.loadDataPages(w.number);
      if (pages.isEmpty &&
          dataPagesStatus == WorkoutStreamHonesty.present) {
        dataPagesStatus = WorkoutStreamHonesty.incomplete;
        dataPagesStored = null;
      } else if (pages.isNotEmpty) {
        dataPagesStored = pages.length;
      }
    }
    if (checkPace) {
      final blocks = await _runSessionStore.loadPaceBlocks(w.number);
      if (blocks.isEmpty &&
          paceBlocksStatus == WorkoutStreamHonesty.present) {
        paceBlocksStatus = WorkoutStreamHonesty.incomplete;
        paceBlocksStored = null;
      } else if (blocks.isNotEmpty) {
        paceBlocksStored = blocks.length;
      }
    }

    return w.copyWith(
      leftoversStatus: leftoversStatus,
      dataPagesStatus: dataPagesStatus,
      paceBlocksStatus: paceBlocksStatus,
      leftoverRefs: leftoverRefs,
      dataPagesStored: dataPagesStored,
      paceBlocksStored: paceBlocksStored,
    );
  }

  /// Write peeled leftover/sample/pace bodies via [RunSessionStore].
  ///
  /// Side-file write failure → stamp [WorkoutStreamHonesty.incomplete] on the
  /// affected streams; Totals scalars remain mergeable (U3 soft-incomplete).
  /// Never logs body payloads — workout # / lengths only.
  ///
  /// Enrichment-monotonic for streams: never overwrite denser data/pace
  /// side-files with a sparser partial payload (prefs merge alone cannot
  /// restore bytes already clobbered on disk). Leftovers replace only when
  /// [parserGeneration] allows (R3 remap) or incoming is denser.
  Future<List<WorkoutSummary>> _persistPeeledSideFiles(
    List<PeeledWorkoutPayload>? peeled,
    List<WorkoutSummary> workouts, {
    required bool softIncomplete,
  }) async {
    if (peeled == null || peeled.isEmpty) {
      return softIncomplete
          ? workouts.map(_bumpSoftIncompleteStreamHonesty).toList()
          : workouts;
    }
    final byNumber = <int, WorkoutSummary>{
      for (final w in workouts) w.number: w,
    };
    final existingByNumber = <int, WorkoutSummary>{
      for (final w in await loadLocal()) w.number: w,
    };
    for (final payload in peeled) {
      final toWrite = await _monotonicPeeledPayload(
        payload,
        existingSummary: existingByNumber[payload.workoutNumber],
      );
      if (!toWrite.hasBodiesToPersist) continue;
      try {
        await _runSessionStore.save(toWrite);
        FosHuaweiLog.i(
          'run-session side-files saved workout=#${toWrite.workoutNumber} '
          'leftovers=${toWrite.totalsLeftovers.length} '
          'dataPages=${toWrite.dataPages.length} '
          'paceBlocks=${toWrite.paceBlocks.length}',
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
          leftoversStatus: toWrite.totalsLeftovers.isNotEmpty
              ? WorkoutStreamHonesty.incomplete
              : existing.leftoversStatus,
          dataPagesStatus: toWrite.dataPages.isNotEmpty
              ? WorkoutStreamHonesty.incomplete
              : existing.dataPagesStatus,
          paceBlocksStatus: toWrite.paceBlocks.isNotEmpty
              ? WorkoutStreamHonesty.incomplete
              : existing.paceBlocksStatus,
        );
      }
    }
    final out = workouts.map((w) => byNumber[w.number] ?? w).toList();
    if (!softIncomplete) return out;
    return out.map(_bumpSoftIncompleteStreamHonesty).toList();
  }

  /// Soft-incomplete with Count>0 but zero arrived pages peels as
  /// [WorkoutStreamHonesty.partial] (and this bump covers older peels that
  /// still said unobserved). Count=0 stays unobserved.
  WorkoutSummary _bumpSoftIncompleteStreamHonesty(WorkoutSummary w) {
    String? bump(String? status, int? countHint) {
      if ((countHint ?? 0) <= 0) return status;
      if (status == null || status == WorkoutStreamHonesty.unobserved) {
        return WorkoutStreamHonesty.partial;
      }
      return status;
    }

    return w.copyWith(
      dataPagesStatus: bump(w.dataPagesStatus, w.dataCount),
      paceBlocksStatus: bump(w.paceBlocksStatus, w.paceCount),
    );
  }

  /// Drop sparser data/pace/leftover bodies so [RunSessionStore.save] cannot
  /// clobber denser on-disk streams. Leftovers may still replace when
  /// [currentRunSessionParserVersion] exceeds the existing row's generation.
  Future<PeeledWorkoutPayload> _monotonicPeeledPayload(
    PeeledWorkoutPayload payload, {
    WorkoutSummary? existingSummary,
  }) async {
    var leftovers = payload.totalsLeftovers;
    var dataPages = payload.dataPages;
    var paceBlocks = payload.paceBlocks;

    if (leftovers.isNotEmpty) {
      final existing =
          await _runSessionStore.loadTotalsLeftovers(payload.workoutNumber);
      final allowReplace = _allowParserReplace(existingSummary);
      if (!allowReplace &&
          _leftoverRichness(existing) > _leftoverRichness(leftovers)) {
        leftovers = const [];
      }
    }
    if (dataPages.isNotEmpty) {
      final existing =
          await _runSessionStore.loadDataPages(payload.workoutNumber);
      if (_pageBodyRichness(existing) > _pageBodyRichness(dataPages)) {
        dataPages = const [];
      }
    }
    if (paceBlocks.isNotEmpty) {
      final existing =
          await _runSessionStore.loadPaceBlocks(payload.workoutNumber);
      if (_pageBodyRichness(existing) > _pageBodyRichness(paceBlocks)) {
        paceBlocks = const [];
      }
    }
    if (identical(leftovers, payload.totalsLeftovers) &&
        identical(dataPages, payload.dataPages) &&
        identical(paceBlocks, payload.paceBlocks)) {
      return payload;
    }
    return PeeledWorkoutPayload(
      workoutNumber: payload.workoutNumber,
      totalsLeftovers: leftovers,
      dataPages: dataPages,
      paceBlocks: paceBlocks,
      leftoversStatus: payload.leftoversStatus,
      dataPagesStatus: payload.dataPagesStatus,
      paceBlocksStatus: payload.paceBlocksStatus,
      observedType: payload.observedType,
    );
  }

  bool _allowParserReplace(WorkoutSummary? existing) {
    if (existing == null) return true;
    final existingGen = existing.parserGeneration ?? 0;
    return currentRunSessionParserVersion > existingGen;
  }

  /// Body count dominates; total byte length next; page count is tie-breaker
  /// only — never let more sparse pages beat denser sample bodies.
  static int _pageBodyRichness(List<PeeledPageBodies> pages) {
    if (pages.isEmpty) return 0;
    var bodies = 0;
    var bytes = 0;
    for (final p in pages) {
      bodies += p.bodies.length;
      for (final b in p.bodies) {
        bytes += b.len;
      }
    }
    return bodies * 1000000 + bytes * 1000 + pages.length;
  }

  static int _leftoverRichness(List<LeftoverTlvBody> bodies) {
    if (bodies.isEmpty) return 0;
    var bytes = 0;
    for (final b in bodies) {
      bytes += b.len;
    }
    return bodies.length * 1000000 + bytes;
  }

  /// Delta-only Count window: cursor − overlap when present; otherwise last
  /// [coldStartWindowDays]. Partials extend the window back to the earliest
  /// partial start (still not a 2022 full-history dump by default).
  ///
  /// [forceFullHistory]: Count from [fullHistoryStartUnix] (POC FALLBACK).
  /// [forceWide14d]: ignore cursor for [coldStartWindowDays] only.
  Future<int> _resolveSyncStartUnix(
    int endUnix, {
    bool forceFullHistory = false,
    bool forceWide14d = false,
  }) async {
    final coldStart = endUnix - coldStartWindowDays * 86400;
    final cursor = _prefs.getInt(GateAPrefs.lastSyncCursor);
    var start = forceFullHistory
        ? fullHistoryStartUnix
        : (forceWide14d || cursor == null || cursor <= 0)
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

  static String _fmtUnix(int unix) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unix * 1000).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<List<WorkoutSummary>> _mergeAndPersist(
    List<WorkoutSummary> incoming,
  ) async {
    final existing = await loadLocal();
    final byNumber = <int, WorkoutSummary>{
      for (final w in existing) w.number: w,
    };
    for (final w in incoming) {
      final prev = byNumber[w.number];
      byNumber[w.number] = prev == null
          ? w
          : WorkoutEnrichmentMerge.mergeRow(
              existing: prev,
              incoming: w,
              currentParserGeneration: currentRunSessionParserVersion,
            );
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
      // Use post-monotonic row so Totals-only soft-incomplete does not clobber
      // richer local swim segments in the canonical side-file.
      final row = byNumber[w.number] ?? w;
      final session = CanonicalSwimSession.fromWorkoutSummary(
        row,
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
