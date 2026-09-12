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
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/data/workout_leftover_store.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/strength_session_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_style_capability_log.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutHistoryRepositoryImpl implements WorkoutHistoryRepository {
  WorkoutHistoryRepositoryImpl({
    required HuaweiLink link,
    required SharedPreferences prefs,
    CanonicalSwimStore? swimStore,
    WorkoutLeftoverStore? leftoverStore,
    Directory? Function()? swimRootOverride,
    RunSessionStore? runSessionStore,
    Directory? Function()? runSessionRootOverride,
    Directory? Function()? leftoverRootOverride,
    Directory? Function()? sideFileRootOverride,
    void Function()? onSyncSettled,
  })  : _link = link,
        _prefs = prefs,
        _swimStore = swimStore ??
            CanonicalSwimStore(rootOverride: swimRootOverride),
        _runSessionStore = runSessionStore ??
            RunSessionStore(rootOverride: runSessionRootOverride),
        _leftoverStore = leftoverStore ??
            WorkoutLeftoverStore(rootOverride: leftoverRootOverride),
        _sideFileRootOverride = sideFileRootOverride,
        _onSyncSettled = onSyncSettled;

  final HuaweiLink _link;
  final SharedPreferences _prefs;
  final CanonicalSwimStore _swimStore;
  final RunSessionStore _runSessionStore;
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

  /// Run/session leftover + stream remap generation (monotonic escape hatch).
  ///
  /// v2: one-shot 14-day wide Count (ignore cursor).
  /// v3: one-shot **full-history** Count from mid-2022 FALLBACK — needed when
  /// the watch still holds Outdoor Runs older than the incremental cursor
  /// (Sep 9 missed after cursor advanced to Sep 10+). Still hint-gated
  /// Data/Pace (no force-empty enrichment).
  static const currentRunSessionParserVersion = 4;

  /// Same floor GB / POC used for first full-history Count testing.
  static const fullHistoryStartUnix = 1_654_819_200; // 2022-06-10

  @override
  bool get isSyncOrMergeInFlight => _link.syncInFlight || _mergeInFlight;

  @override
  bool get lastLeftoverPersistLanded => _lastLeftoverPersistLanded;

  @override
  Future<bool> isGateAPassed() async =>
      _prefs.getBool(GateAPrefs.gateAPassed) ?? false;

  @override
  Future<List<WorkoutSummary>> loadLocal() async {
    final list = await _readRawLocal();
    return _promoteStrengthScalarsFromSideFiles(list);
  }

  /// Prefs-only decode — no leftover promotion (used mid-merge).
  Future<List<WorkoutSummary>> _readRawLocal() async {
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

  /// Promote Load / Recovery / TE from Totals leftovers when prefs scalars are
  /// null (pre-strength Sync left tags `0x0d` / `0x11` unparsed).
  Future<List<WorkoutSummary>> _promoteStrengthScalarsFromSideFiles(
    List<WorkoutSummary> workouts, {
    bool persist = true,
  }) async {
    var changed = false;
    final out = <WorkoutSummary>[];
    for (final w in workouts) {
      if (!isStrengthWorkout(w.type) ||
          (w.load != null &&
              w.recoveryTime != null &&
              w.aerobicEffect != null &&
              w.anaerobicEffect != null)) {
        out.add(w);
        continue;
      }

      List<LeftoverTlvBody> bodies = const [];
      try {
        bodies = await _runSessionStore.loadTotalsLeftovers(w.number);
      } catch (_) {
        // path_provider may be unavailable in unit tests.
      }

      Uint8List? bytes;
      final path = w.leftoverPath;
      if (path != null && path.isNotEmpty) {
        bytes = await _leftoverStore.loadAtRelativePath(path);
      } else if ((w.leftoverLen ?? 0) > 0 || w.leftoverPresent == true) {
        bytes = await _leftoverStore.load(
          workoutNumber: w.number,
          startTime: w.startTime,
        );
      }

      final next = promoteStrengthScalarsFromLeftovers(
        w,
        leftoverBodies: bodies,
        leftoverBytes: bytes,
      );
      if (next.load != w.load ||
          next.recoveryTime != w.recoveryTime ||
          next.aerobicEffect != w.aerobicEffect ||
          next.anaerobicEffect != w.anaerobicEffect ||
          next.trainingPoints != w.trainingPoints) {
        changed = true;
        FosHuaweiLog.i(
          'strength scalar promote number=${w.number} '
          'load=${next.load} recovery=${next.recoveryTime} '
          'aerobic=${next.aerobicEffect} anaerobic=${next.anaerobicEffect}',
          op: 'sync',
        );
      }
      out.add(next);
    }

    if (persist && changed && _gateStillPassed()) {
      await _prefs.setString(
        GateAPrefs.workoutsJson,
        jsonEncode(out.map((w) => w.toJson()).toList()),
      );
    }
    return out;
  }

  @override
  Future<void> clearLocal() async {
    await _leftoverStore.clearLocal();
    await _wipeSampleDir();
    try {
      await _runSessionStore.clearLocal();
    } catch (_) {
      // Best-effort — path_provider may be unavailable in unit tests.
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
    const forceWide14d = false;
    final startUnix = await _resolveSyncStartUnix(
      endUnix,
      forceFullHistory: useFullHistory,
      forceWide14d: forceWide14d,
    );
    final windowLabel = useFullHistory ? 'full-history' : 'delta';
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
      // Totals-prefix stuck must not advance past unfetched Count numbers.
      final advanceCursor = result.status != WorkoutSyncStatus.stuck;

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

      if (!_gateStillPassed()) {
        return const Left(ServerFailure('Gate cleared — sync discarded'));
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
      final merged = await _mergeAndPersist(
        stamped,
        advanceCursor: advanceCursor,
      );
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
              WorkoutSyncStatus.notReady =>
                'Watch still connecting — wait until linked, then Force Sync again',
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
  /// Late merge after Forget / Gate A clear is a no-op (identity wiped).
  bool _gateStillPassed() => _prefs.getBool(GateAPrefs.gateAPassed) ?? false;

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
      // Sanitize totals-only "partial" before clock-3 widening so legacy prefs
      // rows cannot reopen historical windows (incoming maps already sanitized).
      final status = _sanitizeEnrichmentStatus(w).enrichmentStatus;
      if (status == 'partial') {
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

      final existing = await _readRawLocal();
      final byNumber = <int, WorkoutSummary>{
        for (final w in existing) w.number: w,
      };

      final prepared = <WorkoutSummary>[];
      for (final w in incoming) {
        // Gate before side-file writes — late merge after Forget is a no-op.
        if (!_gateStillPassed()) {
          _lastLeftoverPersistLanded = false;
          return const [];
        }
        final prior = byNumber[w.number];
        // Same number + new startTime: drop prior leftover/sample side-files
        // so orphans do not accumulate across session reuse.
        if (prior != null && prior.startTime != w.startTime) {
          await _deleteSideArtifactsBestEffort(prior);
        }
        // Do not let totals-only rows carry enrichmentStatus=partial — that
        // widens _resolveSyncStartUnix (clock 3) and can reopen 2022.
        final sanitized = _sanitizeEnrichmentStatus(w);
        // Different startTime = new session identity — do not merge scalars
        // from the prior row (load/HR/etc must not glue across reuse).
        final runMerged = (prior == null || prior.startTime != w.startTime)
            ? sanitized
            : WorkoutEnrichmentMerge.mergeRow(
                existing: prior,
                incoming: sanitized,
                currentParserGeneration: currentRunSessionParserVersion,
              );
        final united = await _unionWorkout(prior, runMerged);
        prepared.add(await _persistSideArtifacts(united));
      }

      for (final w in prepared) {
        byNumber[w.number] = w;
      }
      final merged = byNumber.values.toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));

      // Repair strength Load/Recovery from leftovers before prefs commit when
      // this Sync did not re-deliver those scalars (delta miss / old parse).
      final promoted = await _promoteStrengthScalarsFromSideFiles(
        merged,
        persist: false,
      );

      // TOCTOU vs Forget: re-check immediately before prefs commit.
      if (!_gateStillPassed()) {
        _lastLeftoverPersistLanded = false;
        return const [];
      }

      await _prefs.setString(
        GateAPrefs.workoutsJson,
        jsonEncode(promoted.map((w) => w.toJson()).toList()),
      );

      // If Forget cleared Gate A during setString, roll back the index write.
      if (!_gateStillPassed()) {
        await _prefs.remove(GateAPrefs.workoutsJson);
        _lastLeftoverPersistLanded = false;
        return const [];
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final swimSessions = <CanonicalSwimSession>[];
      for (final w in prepared) {
        if (!_gateStillPassed()) {
          _lastLeftoverPersistLanded = false;
          return const [];
        }
        // Use post-monotonic row so Totals-only soft-incomplete does not clobber
        // richer local swim segments in the canonical side-file.
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
        if (!_gateStillPassed()) {
          _lastLeftoverPersistLanded = false;
          return const [];
        }
        await _swimStore.saveAll(swimSessions);
      }

      // Totals-prefix stuck must not advance past unfetched Count numbers.
      if (advanceCursor) {
        if (!_gateStillPassed()) {
          _lastLeftoverPersistLanded = false;
          return const [];
        }
        var maxEnd = 0;
        for (final w in promoted) {
          if (w.endTime > maxEnd) maxEnd = w.endTime;
        }
        if (maxEnd > 0) {
          await _prefs.setInt(GateAPrefs.lastSyncCursor, maxEnd + 1);
        }
      }
      return promoted;
    } finally {
      _mergeInFlight = false;
    }
  }

  WorkoutSummary _sanitizeEnrichmentStatus(WorkoutSummary w) {
    if (w.enrichmentStatus != 'partial') return w;
    // Soft-incomplete / run stream honesty must survive clock-3 sanitize.
    if (w.dataPagesStatus != null ||
        w.paceBlocksStatus != null ||
        w.leftoversStatus != null) {
      return w;
    }
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
  ///
  /// Run-session honesty fields already on [incoming] (from
  /// [WorkoutEnrichmentMerge.mergeRow]) are preserved.
  Future<WorkoutSummary> _unionWorkout(
    WorkoutSummary? local,
    WorkoutSummary incoming,
  ) async {
    if (local == null || local.startTime != incoming.startTime) {
      return incoming;
    }

    final leftover = await _unionLeftover(local, incoming);
    final sample = _unionSampleRefs(local, incoming);
    final segments = _unionSegments(local, incoming);

    return incoming.copyWith(
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
      clearLeftoverPath: leftover.leftoverPath == null,
      clearLeftoverBytes: leftover.leftoverBytes == null,
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
  /// Ghost index (present/path/len but missing file) + incoming body → adopt
  /// incoming so a failed persist cannot permanently block rewrite.
  Future<
      ({
        int? leftoverLen,
        bool? leftoverPresent,
        String? leftoverPath,
        Uint8List? leftoverBytes,
      })> _unionLeftover(WorkoutSummary local, WorkoutSummary incoming) async {
    final incomingHasBody =
        incoming.leftoverBytes != null && incoming.leftoverBytes!.isNotEmpty;
    final localHasIndex = local.leftoverPresent == true ||
        (local.leftoverPath != null && local.leftoverPath!.isNotEmpty) ||
        (local.leftoverLen != null && local.leftoverLen! > 0);

    if (incomingHasBody && !localHasIndex) {
      return (
        leftoverLen: incoming.leftoverLen ?? incoming.leftoverBytes!.length,
        leftoverPresent: true,
        leftoverPath: incoming.leftoverPath,
        leftoverBytes: incoming.leftoverBytes,
      );
    }
    if (localHasIndex) {
      if (incomingHasBody) {
        final path = local.leftoverPath;
        final onDisk = path != null && path.isNotEmpty
            ? await _leftoverStore.loadAtRelativePath(path)
            : null;
        if (onDisk == null || onDisk.isEmpty) {
          // Ghost index — file missing; rewrite from incoming body.
          return (
            leftoverLen: incoming.leftoverLen ?? incoming.leftoverBytes!.length,
            leftoverPresent: true,
            leftoverPath: incoming.leftoverPath,
            leftoverBytes: incoming.leftoverBytes,
          );
        }
      }
      // Keep local — including when both have bodies and the file exists.
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
    // Late Forget / Gate A clear — do not create new side-files.
    if (!_gateStillPassed()) {
      _lastLeftoverPersistLanded = false;
      return w.copyWith(clearLeftoverBytes: true);
    }

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
      // Native may have spilled a large body to leftoverPath already.
      leftoverPresent ??=
          leftoverPath != null && leftoverPath.isNotEmpty && (leftoverLen ?? 0) > 0
              ? true
              : false;
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

  /// Best-effort delete leftover + sample side-files for a replaced session.
  Future<void> _deleteSideArtifactsBestEffort(WorkoutSummary prior) async {
    final leftoverPath = prior.leftoverPath;
    if (leftoverPath != null && leftoverPath.isNotEmpty) {
      await _leftoverStore.deleteAtRelativePath(leftoverPath);
    } else if ((prior.leftoverLen ?? 0) > 0 || prior.leftoverPresent == true) {
      // Index without path — try conventional identity path.
      await _leftoverStore.delete(
        workoutNumber: prior.number,
        startTime: prior.startTime,
      );
    }
    final samplePath = prior.samplePath;
    if (samplePath != null && samplePath.isNotEmpty) {
      try {
        final root = await _sideFileRoot();
        if (root != null) {
          final file = File('${root.path}/$samplePath');
          if (await file.exists()) await file.delete();
        }
      } catch (_) {
        // Best-effort orphan cleanup.
      }
    }
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
