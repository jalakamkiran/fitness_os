import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/observability/trusleep_timestamp_observe.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/domain/sleep_day.dart';
import 'package:fitness_os/features/vitals/domain/sleep_hr_window.dart';
import 'package:fitness_os/features/vitals/domain/trusleep_sleep_sot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VitalsRepositoryImpl implements VitalsRepository {
  VitalsRepositoryImpl({
    required HuaweiLink link,
    required SharedPreferences prefs,
    Directory? Function()? sideFileRootOverride,
  })  : _link = link,
        _prefs = prefs,
        _sideFileRootOverride = sideFileRootOverride;

  final HuaweiLink _link;
  final SharedPreferences _prefs;
  final Directory? Function()? _sideFileRootOverride;

  /// Bumped when activity Sync merge / SoT rules change (forces one wide pull).
  /// v2: SEQUENCE_DATA TruSleep summary+stages productized — one 14d re-pull.
  /// v3: SEQUENCE-first overnight main + nocturnal ≤90m coalesce.
  static const currentActivitySyncImplVersion = 3;

  /// Overnight-scale overlap when advancing from [GateAPrefs.lastActivitySyncCursor].
  static const activityCursorOverlapSec = 6 * 3600;

  /// ~30m Health vs TruSleep shift — join message stages onto file windows.
  static const stageAttachBufferSec = 30 * 60;

  /// Set when prefs JSON is corrupt — fail-closed; empty sync must not "confirm" wipe.
  bool _sleepLoadFailed = false;
  bool _hrLoadFailed = false;
  bool _fitnessTotalsLoadFailed = false;
  bool _mergeInFlight = false;

  @override
  Future<bool> isGateAPassed() async =>
      _prefs.getBool(GateAPrefs.gateAPassed) ?? false;

  @override
  bool get isSyncOrMergeInFlight => _link.syncInFlight || _mergeInFlight;

  @override
  bool get sessionReady => _link.sessionReady;

  @override
  Future<AutoTrackingEnableResult?> loadLastEnable() async {
    return AutoTrackingEnableResult.tryParsePrefs(
      _prefs.getString(GateAPrefs.lastAutoTrackingEnableJson),
    );
  }

  @override
  Future<List<SleepSessionSummary>> loadSleepSessions() async {
    final raw = _prefs.getString(GateAPrefs.sleepSessionsJson);
    if (raw == null || raw.isEmpty) {
      _sleepLoadFailed = false;
      return const [];
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _sleepLoadFailed = false;
      return list
          .whereType<Map>()
          .map((e) => SleepSessionSummary.fromMap(Map<String, dynamic>.from(e)))
          .where((s) => s.beginUnix > 0 && s.endUnix > s.beginUnix)
          .toList()
        ..sort((a, b) => b.beginUnix.compareTo(a.beginUnix));
    } catch (_) {
      _sleepLoadFailed = true;
      throw const FormatException('Corrupt sleep_sessions_json');
    }
  }

  @override
  Future<List<SleepStageSummary>> loadSleepStages(
    SleepSessionSummary session,
  ) async {
    if (session.beginUnix <= 0 || session.endUnix <= session.beginUnix) {
      return const [];
    }
    final root = await _sideFileRoot();
    if (root == null) return const [];
    final file = File(_stagesFilePath(root, session));
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const [];
      final raw = decoded['stages'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => SleepStageSummary.fromMap(Map<String, dynamic>.from(e)))
          .where((s) => s.timestampUnix > 0 && s.durationMin > 0)
          .toList()
        ..sort((a, b) => a.timestampUnix.compareTo(b.timestampUnix));
    } catch (_) {
      // Fail-closed: corrupt stage file must not wipe begin/end prefs siblings.
      return const [];
    }
  }

  @override
  Future<List<DailyHrDaySummary>> loadDailyHr() async {
    final raw = _prefs.getString(GateAPrefs.dailyHrJson);
    if (raw == null || raw.isEmpty) {
      _hrLoadFailed = false;
      return const [];
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _hrLoadFailed = false;
      return list
          .whereType<Map>()
          .map((e) => DailyHrDaySummary.fromMap(Map<String, dynamic>.from(e)))
          .where((d) => d.dayKey.isNotEmpty)
          .toList()
        ..sort((a, b) => b.dayKey.compareTo(a.dayKey));
    } catch (_) {
      _hrLoadFailed = true;
      throw const FormatException('Corrupt daily_hr_json');
    }
  }

  @override
  Future<List<DailyHrSample>> loadDailyHrSeries(String dayKey) async {
    if (dayKey.isEmpty) return const [];
    final root = await _sideFileRoot();
    if (root == null) return const [];
    final file = File(_seriesFilePath(root, dayKey));
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const [];
      final raw = decoded['samples'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => DailyHrSample.fromMap(Map<String, dynamic>.from(e)))
          .where((s) => s.bpm > 0 && s.timestampUnix > 0)
          .toList()
        ..sort((a, b) => a.timestampUnix.compareTo(b.timestampUnix));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<DailyHrSample>> loadSleepHrWindow({
    required int beginUnix,
    required int endUnix,
  }) async {
    final dayKeys = sleepHrDayKeys(beginUnix: beginUnix, endUnix: endUnix);
    if (dayKeys.isEmpty) return const [];
    final all = <DailyHrSample>[];
    for (final dayKey in dayKeys) {
      all.addAll(await loadDailyHrSeries(dayKey));
    }
    return windowSleepHrSamples(
      samples: all,
      beginUnix: beginUnix,
      endUnix: endUnix,
    );
  }

  @override
  Future<bool> isSleepEnrichPresent(SleepSessionSummary session) async {
    final root = await _sideFileRoot();
    if (root == null) return false;
    final file = File(_enrichFilePath(root, session));
    if (!await file.exists()) return false;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return false;
      return decoded['present'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<TruSleepSequenceSession?> loadTruSleepSummary(
    SleepSessionSummary session,
  ) async {
    final root = await _sideFileRoot();
    if (root == null) return null;
    final file = File(_enrichFilePath(root, session));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final refs = decoded['refs'];
      if (refs is! Map) return null;
      final raw = refs['trusleepSummary'];
      if (raw is! Map) return null;
      final summary =
          TruSleepSequenceSession.fromMap(Map<String, dynamic>.from(raw));
      if (summary.beginUnix <= 0 || summary.endUnix <= summary.beginUnix) {
        return null;
      }
      return summary;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> loadFeelOnWake(SleepSessionSummary session) async {
    final map = _feelOnWakeMap();
    final value = map[session.mergeKey];
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<void> saveFeelOnWake(
    SleepSessionSummary session,
    String answer,
  ) async {
    if (answer.isEmpty) return;
    final map = _feelOnWakeMap();
    if (map.containsKey(session.mergeKey)) return;
    map[session.mergeKey] = answer;
    await _prefs.setString(GateAPrefs.sleepFeelOnWakeJson, jsonEncode(map));
  }

  @override
  Future<List<SleepSessionSummary>> loadSleepSessionsForMonth({
    required int year,
    required int month,
  }) async {
    if (month < 1 || month > 12) return const [];
    final sessions = await loadSleepSessions();
    return sessions.where((s) {
      final end = DateTime.fromMillisecondsSinceEpoch(s.endUnix * 1000);
      return end.year == year && end.month == month;
    }).toList();
  }

  @override
  Future<List<FitnessTotalsDay>> loadFitnessTotals() async {
    final raw = _prefs.getString(GateAPrefs.fitnessTotalsDayJson);
    if (raw == null || raw.isEmpty) {
      _fitnessTotalsLoadFailed = false;
      return const [];
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _fitnessTotalsLoadFailed = false;
      return list
          .whereType<Map>()
          .map((e) => FitnessTotalsDay.fromMap(Map<String, dynamic>.from(e)))
          .where((d) => d.dayKey.isNotEmpty)
          .toList()
        ..sort((a, b) => b.dayKey.compareTo(a.dayKey));
    } catch (_) {
      _fitnessTotalsLoadFailed = true;
      throw const FormatException('Corrupt fitness_totals_day_json');
    }
  }

  @override
  Future<FitnessTotalsDay?> loadFitnessTotalsForDay(String dayKey) async {
    if (dayKey.isEmpty) return null;
    try {
      final days = await loadFitnessTotals();
      for (final d in days) {
        if (d.dayKey == dayKey) return d;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch() async {
    if (!await isGateAPassed()) {
      return const Left(
        ServerFailure('Gate A unlock required before Sync'),
      );
    }

    // Probe prefs so corrupt JSON sets fail-closed flags before empty handling.
    await _probeLocalLoads();

    _mergeInFlight = true;
    try {
      final last = await loadLastEnable();
      final endUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final storedImpl =
          _prefs.getInt(GateAPrefs.activitySyncImplVersion) ?? 0;
      final forceWide = storedImpl < currentActivitySyncImplVersion;
      if (forceWide) {
        // One-shot clear of Sync-fed continuous HR residue on strip bump.
        await _clearDailyHrResidue();
      }
      final startUnix = await _resolveActivitySyncStartUnix(endUnix);
      final result = await _link.syncActivity(
        startUnix: startUnix,
        endUnix: endUnix,
        // Force sleep pull: always re-arm TruSleep soft-enable.
        skipTruSleepSoft: false,
        // Native Sync ignores auto-HR soft; keep channel arg for compat.
        skipAutoHrSoft: true,
      );

      // Late merge after Forget / identity wipe — no-op.
      if (!_gateStillPassed()) {
        return const Left(ServerFailure('Gate cleared — sync discarded'));
      }

      switch (result.status) {
        case ActivitySyncStatus.notReady:
          return Left(
            ServerFailure(result.message ?? 'Session not ready — reconnect'),
          );
        case ActivitySyncStatus.busy:
          return Left(
            ServerFailure(
              result.message ?? 'Another Sync is already in progress',
            ),
          );
        case ActivitySyncStatus.error:
          return Left(ServerFailure(result.message ?? 'Sync failed'));
        case ActivitySyncStatus.empty:
          if (_sleepLoadFailed || _hrLoadFailed || _fitnessTotalsLoadFailed) {
            return const Left(
              ServerFailure('Local vitals store unreadable — not overwriting'),
            );
          }
          if (forceWide && _gateStillPassed()) {
            await _prefs.setInt(
              GateAPrefs.activitySyncImplVersion,
              currentActivitySyncImplVersion,
            );
          }
          final sleep = await _safeLoadSleep();
          final hr = await _safeLoadHr();
          return Right(
            VitalsSnapshot(
              sleepSessions: sleep,
              dailyHr: hr,
              message: _syncEmptyMessage(
                lastEnable: last,
                enableSkipped: result.enableSkipped,
                hrEmpty: hr.isEmpty,
              ),
              enableSkipped: result.enableSkipped,
            ),
          );
        case ActivitySyncStatus.ok:
        case ActivitySyncStatus.partialBatch:
        case ActivitySyncStatus.stuck:
          if (!_gateStillPassed()) {
            return const Left(ServerFailure('Gate cleared — sync discarded'));
          }
          final merge = await _mergeContainers(result);
          if (forceWide && _gateStillPassed()) {
            await _prefs.setInt(
              GateAPrefs.activitySyncImplVersion,
              currentActivitySyncImplVersion,
            );
          }
          final allowCursorAdvance =
              result.status == ActivitySyncStatus.ok && merge.fileSotUpserted;
          await _maybeAdvanceActivityCursor(
            fileSotUpserted: allowCursorAdvance,
            maxUpsertedEndUnix: merge.maxUpsertedEndUnix,
          );
          final sleep = await _safeLoadSleep();
          // Temporary: log displayed timings + message deltas (~5–6 Syncs).
          await TruSleepTimestampObserve.report(
            displayedSessions: sleep,
            messageSessions: result.sleepSessions,
            enrich: result.sleepEnrich,
            watchClock: result.watchClock,
          );
          final hr = await _safeLoadHr();
          final partial = result.status == ActivitySyncStatus.partialBatch ||
              result.status == ActivitySyncStatus.stuck;
          final enableMsg = _syncEnableMessage(
            lastEnable: last,
            enableSkipped: result.enableSkipped,
          );
          return Right(
            VitalsSnapshot(
              sleepSessions: sleep,
              dailyHr: hr,
              message: partial
                  ? (result.message ?? 'Partial sync — some containers missing')
                  : enableMsg,
              partial: partial,
              enableSkipped: result.enableSkipped,
            ),
          );
      }
    } finally {
      _mergeInFlight = false;
    }
  }

  /// Wide window until cursor sticks; then cursor − overnight overlap.
  Future<int> _resolveActivitySyncStartUnix(int endUnix) async {
    final wideStart = endUnix - HuaweiLink.activityWindowDays * 24 * 60 * 60;
    final storedImpl =
        _prefs.getInt(GateAPrefs.activitySyncImplVersion) ?? 0;
    if (storedImpl < currentActivitySyncImplVersion) {
      return wideStart;
    }
    final cursor = _prefs.getInt(GateAPrefs.lastActivitySyncCursor);
    if (cursor == null || cursor <= 0) {
      return wideStart;
    }
    final withOverlap = cursor - activityCursorOverlapSec;
    if (withOverlap < wideStart) return wideStart;
    if (withOverlap > endUnix) return endUnix;
    return withOverlap;
  }

  Future<void> _maybeAdvanceActivityCursor({
    required bool fileSotUpserted,
    required int maxUpsertedEndUnix,
  }) async {
    if (!fileSotUpserted || maxUpsertedEndUnix <= 0) return;
    if (!_gateStillPassed()) return;
    await _prefs.setInt(
      GateAPrefs.lastActivitySyncCursor,
      maxUpsertedEndUnix + 1,
    );
  }

  bool _hasFileSleepSotFlip() =>
      _prefs.getBool(GateAPrefs.fileSleepSotActive) ?? false;

  Future<void> _clearDailyHrResidue() async {
    await _prefs.remove(GateAPrefs.dailyHrJson);
    final root = await _sideFileRoot();
    if (root == null) return;
    final dir = Directory('${root.path}/${GateAPrefs.dailyHrSeriesDir}');
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  @override
  Future<Either<Failure, AutoTrackingEnableResult>> enableAutoTracking() async {
    if (!await isGateAPassed()) {
      return const Left(
        ServerFailure('Gate A unlock required before Enable'),
      );
    }
    if (!sessionReady) {
      return const Left(
        ServerFailure('Session not ready — reconnect first'),
      );
    }

    _mergeInFlight = true;
    try {
      final result = await _link.enableAutoTracking();
      switch (result.status) {
        case AutoTrackingEnableStatus.notReady:
          return Left(
            ServerFailure(result.message ?? 'Session not ready — reconnect'),
          );
        case AutoTrackingEnableStatus.busy:
          return Left(
            ServerFailure(
              result.message ?? 'Another Sync is already in progress',
            ),
          );
        case AutoTrackingEnableStatus.error:
          return Left(ServerFailure(result.message ?? 'Enable failed'));
        case AutoTrackingEnableStatus.ok:
          final stamped = AutoTrackingEnableResult(
            status: result.status,
            overall: result.overall,
            message: result.message,
            features: result.features,
            completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
          if (_gateStillPassed() && _deviceRemembered()) {
            await _prefs.setString(
              GateAPrefs.lastAutoTrackingEnableJson,
              jsonEncode(stamped.toPrefsJson()),
            );
          }
          return Right(stamped);
      }
    } finally {
      _mergeInFlight = false;
    }
  }

  bool _deviceRemembered() {
    final mac = _prefs.getString(GateAPrefs.rememberedMac);
    return mac != null && mac.isNotEmpty;
  }

  String _syncEmptyMessage({
    required AutoTrackingEnableResult? lastEnable,
    required bool enableSkipped,
    required bool hrEmpty,
  }) {
    if (hrEmpty) {
      final hrOutcome = lastEnable?.outcomeFor('auto_hr');
      if (hrOutcome == 'armed') {
        // Sync no longer refills whole-day HR — do not promise wear→Sync BPM.
        return 'No new sleep data in range (continuous HR is not synced)';
      }
      if (hrOutcome == 'skipped' ||
          hrOutcome == 'failed' ||
          hrOutcome == 'timed_out') {
        return 'No new sleep data in range — Enable auto-tracking if needed';
      }
      if (lastEnable == null) {
        return 'No new sleep data in range';
      }
    }
    if (lastEnable == null && enableSkipped) {
      return 'Enable skipped — watch may need TruSleep armed';
    }
    return 'No new sleep data in range';
  }

  String? _syncEnableMessage({
    required AutoTrackingEnableResult? lastEnable,
    required bool enableSkipped,
  }) {
    if (lastEnable != null) {
      final hr = lastEnable.outcomeFor('auto_hr');
      if (hr == 'failed' || hr == 'timed_out' || hr == 'skipped') {
        return 'Synced — auto-HR last Enable was $hr; retry Enable if needed';
      }
      return null;
    }
    if (enableSkipped) return 'Synced (enable skipped on watch)';
    return null;
  }

  bool _gateStillPassed() => _prefs.getBool(GateAPrefs.gateAPassed) ?? false;

  Future<void> _probeLocalLoads() async {
    try {
      await loadSleepSessions();
    } catch (_) {}
    try {
      await loadDailyHr();
    } catch (_) {}
    try {
      await loadFitnessTotals();
    } catch (_) {}
  }

  Future<_SleepMergeResult> _mergeContainers(ActivitySyncResult result) async {
    if (!_gateStillPassed()) {
      return const _SleepMergeResult();
    }
    final completed = result.completedContainers;
    final intervals = _collectStateIntervals(result.sleepEnrich);
    final sequences = _collectSequenceSessions(result.sleepEnrich);
    var merge = const _SleepMergeResult();

    if (intervals.isNotEmpty || sequences.isNotEmpty) {
      merge = await _mergeFileSleepSot(
        intervals: intervals,
        sequences: sequences,
        messageSessions: result.sleepSessions,
        enrich: result.sleepEnrich,
      );
    } else if (completed.contains('sleep') && !_sleepLoadFailed) {
      if (_hasFileSleepSotFlip()) {
        // Messages never own begin/end after flip — stages only.
        await _attachMessageStagesOntoFileSot(result.sleepSessions);
      } else {
        // Pre-flip interim: message-path SoT until first file upsert.
        await _mergeSleep(result.sleepSessions);
      }
    }
    if (!_gateStillPassed()) return merge;

    // Continuous HR stripped — never merge daily_hr from Sync.
    if (!_gateStillPassed()) return merge;
    // FitnessTotals: merge even all-zero scalar rows.
    if (completed.contains('fitness_totals') && !_fitnessTotalsLoadFailed) {
      await _mergeFitnessTotals(result.fitnessTotals);
    }
    if (!_gateStillPassed()) return merge;
    // Enrich absent ⇒ leave prior enrich refs untouched (monotonic).
    if (intervals.isEmpty &&
        sequences.isEmpty &&
        result.sleepEnrich.isNotEmpty) {
      await _mergeSleepEnrich(result.sleepEnrich);
    }
    return merge;
  }

  List<SleepStateInterval> _collectStateIntervals(
    List<SleepEnrichOutcome> enrich,
  ) {
    final out = <SleepStateInterval>[];
    for (final o in enrich) {
      if (!o.present || o.stateIntervals.isEmpty) continue;
      out.addAll(o.stateIntervals);
      break; // full list is on first row (native contract)
    }
    return out;
  }

  List<TruSleepSequenceSession> _collectSequenceSessions(
    List<SleepEnrichOutcome> enrich,
  ) {
    for (final o in enrich) {
      if (!o.present || o.sequenceSessions.isEmpty) continue;
      return List<TruSleepSequenceSession>.from(o.sequenceSessions);
    }
    return const [];
  }

  Future<_SleepMergeResult> _mergeFileSleepSot({
    required List<SleepStateInterval> intervals,
    required List<TruSleepSequenceSession> sequences,
    required List<SleepSessionSummary> messageSessions,
    required List<SleepEnrichOutcome> enrich,
  }) async {
    if (!_gateStillPassed()) return const _SleepMergeResult();
    // Micro-merge ≤3m → SEQUENCE scientific mains carve overlaps → nocturnal
    // coalesce leftovers only (never glue-then-shrink under SEQUENCE bounds).
    final built = intervals.isNotEmpty
        ? _buildFileSessionsWithSequenceCarve(intervals, sequences)
        : _scientificMainsFromSequences(sequences);
    if (built.isEmpty) return const _SleepMergeResult();

    final existing = await _safeLoadSleep();
    if (!_gateStillPassed()) return const _SleepMergeResult();

    // Upsert: drop prior sessions that overlap this pull's file sessions.
    final retained = existing
        .where((e) => !built.any((b) => _sleepOverlaps(e, b)))
        .toList();
    final replaced = existing
        .where((e) => built.any((b) => _sleepOverlaps(e, b)))
        .toList();

    final withStages = <SleepSessionSummary>[];
    // Load prior stages before deleting replaced side-files (monotonic).
    final priorStages = <String, List<SleepStageSummary>>{};
    for (final r in replaced) {
      priorStages[r.mergeKey] = await loadSleepStages(r);
    }
    for (final file in built) {
      final seq = _bestUsableSequenceForWindow(file, sequences);
      var stages = (seq != null && seq.productStages.isNotEmpty)
          ? seq.productStages
          : _stagesForFileWindow(file, messageSessions);
      if (stages.isEmpty) {
        stages = _priorStagesForWindow(file, replaced, priorStages);
      }
      withStages.add(
        SleepSessionSummary(
          beginUnix: file.beginUnix,
          endUnix: file.endUnix,
          wireType: file.wireType, // null → mergeKey ends with ':'
          stages: stages,
        ),
      );
    }

    await _migrateFeelOnWake(
      fromSessions: replaced,
      toSessions: withStages,
    );
    if (!_gateStillPassed()) return const _SleepMergeResult();

    final merged = <SleepSessionSummary>[...retained, ...withStages]
      ..sort((a, b) => b.beginUnix.compareTo(a.beginUnix));

    await _prefs.setString(
      GateAPrefs.sleepSessionsJson,
      jsonEncode(merged.map((s) => s.toJson()).toList()),
    );
    // Flip marker independent of cursor — R2 holds even when partial skips cursor.
    await _prefs.setBool(GateAPrefs.fileSleepSotActive, true);

    // Rewrite stages under file mergeKeys; remove overlapping priors' files.
    await _deleteStageFiles(replaced);
    await _persistSleepStages(
      withStages.where((s) => s.stages.isNotEmpty).toList(),
    );

    // Rewrite enrich under file windows (monotonic present refs + summary).
    await _rewriteEnrichForFileSessions(
      withStages,
      enrich,
      replaced: replaced,
    );

    var maxEnd = 0;
    for (final s in withStages) {
      if (s.endUnix > maxEnd) maxEnd = s.endUnix;
    }
    return _SleepMergeResult(
      fileSotUpserted: true,
      maxUpsertedEndUnix: maxEnd,
    );
  }

  /// Micro-merge intervals, emit scientific SEQUENCE mains, coalesce leftovers.
  List<SleepSessionSummary> _buildFileSessionsWithSequenceCarve(
    List<SleepStateInterval> intervals,
    List<TruSleepSequenceSession> sequences,
  ) {
    final micro = TruSleepSleepSot.gapMergeChains(intervals)
        .map(
          (c) => SleepSessionSummary(
            beginUnix: c.beginUnix,
            endUnix: c.endUnix,
          ),
        )
        .toList();
    final mains = _pickScientificMains(sequences);
    if (mains.isEmpty) {
      return SleepDay.coalesceNocturnalSessions(micro);
    }

    final mainSessions = mains
        .map(_sessionFromScientificSequence)
        .where((s) => s.beginUnix > 0 && s.endUnix > s.beginUnix)
        .toList();

    final leftovers = micro
        .where(
          (frag) => !mainSessions.any((main) => _sleepOverlaps(frag, main)),
        )
        .toList();
    final coalescedLeftovers = SleepDay.coalesceNocturnalSessions(leftovers);
    return [...mainSessions, ...coalescedLeftovers]
      ..sort((a, b) => a.beginUnix.compareTo(b.beginUnix));
  }

  /// SEQUENCE-only path: scientific mains at fallAsleep→wakeup (else begin→end).
  List<SleepSessionSummary> _scientificMainsFromSequences(
    List<TruSleepSequenceSession> sequences,
  ) {
    return _pickScientificMains(sequences)
        .map(_sessionFromScientificSequence)
        .where((s) => s.beginUnix > 0 && s.endUnix > s.beginUnix)
        .toList()
      ..sort((a, b) => a.beginUnix.compareTo(b.beginUnix));
  }

  /// One scientific SEQUENCE per sleep-day: higher score, else longer span.
  List<TruSleepSequenceSession> _pickScientificMains(
    List<TruSleepSequenceSession> sequences,
  ) {
    final scientific = sequences.where((s) => s.isScientific).toList();
    if (scientific.isEmpty) return const [];

    final byDay = <DateTime, TruSleepSequenceSession>{};
    for (final s in scientific) {
      final main = _sessionFromScientificSequence(s);
      final day = SleepDay.sleepDayIdForSession(main);
      final prior = byDay[day];
      if (prior == null || _scientificMainBetter(s, prior)) {
        byDay[day] = s;
      }
    }
    return byDay.values.toList()
      ..sort((a, b) => a.beginUnix.compareTo(b.beginUnix));
  }

  bool _scientificMainBetter(
    TruSleepSequenceSession a,
    TruSleepSequenceSession b,
  ) {
    final sa = a.sleepScore ?? 0;
    final sb = b.sleepScore ?? 0;
    if (sa != sb) return sa > sb;
    final da = _sequenceMainSpanSec(a);
    final db = _sequenceMainSpanSec(b);
    return da > db;
  }

  int _sequenceMainSpanSec(TruSleepSequenceSession s) {
    final main = _sessionFromScientificSequence(s);
    return main.endUnix - main.beginUnix;
  }

  SleepSessionSummary _sessionFromScientificSequence(
    TruSleepSequenceSession s,
  ) {
    final begin = (s.fallAsleepUnix != null && s.fallAsleepUnix! > 0)
        ? s.fallAsleepUnix!
        : s.beginUnix;
    final end = (s.wakeupUnix != null && s.wakeupUnix! > begin)
        ? s.wakeupUnix!
        : s.endUnix;
    return SleepSessionSummary(beginUnix: begin, endUnix: end);
  }

  List<SleepStageSummary> _stagesForFileWindow(
    SleepSessionSummary file,
    List<SleepSessionSummary> messages,
  ) {
    final buffered = SleepSessionSummary(
      beginUnix: file.beginUnix - stageAttachBufferSec,
      endUnix: file.endUnix + stageAttachBufferSec,
    );
    final stages = <SleepStageSummary>[];
    for (final msg in messages) {
      if (!_sleepOverlaps(buffered, msg)) continue;
      for (final st in msg.stages) {
        final stageEnd = st.timestampUnix + st.durationMin * 60;
        if (st.timestampUnix < buffered.endUnix &&
            stageEnd > buffered.beginUnix) {
          stages.add(st);
        }
      }
    }
    stages.sort((a, b) => a.timestampUnix.compareTo(b.timestampUnix));
    return stages;
  }

  /// Prefer SEQUENCE session with greatest overlap vs file window.
  TruSleepSequenceSession? _bestSequenceForWindow(
    SleepSessionSummary file,
    List<TruSleepSequenceSession> sequences,
  ) {
    TruSleepSequenceSession? best;
    var bestOverlap = 0;
    for (final s in sequences) {
      final begin = file.beginUnix > s.beginUnix ? file.beginUnix : s.beginUnix;
      final end = file.endUnix < s.endUnix ? file.endUnix : s.endUnix;
      final o = end - begin;
      if (o > bestOverlap) {
        bestOverlap = o;
        best = s;
      }
    }
    return bestOverlap > 0 ? best : null;
  }

  /// Ignore thin SEQUENCE stubs (score=0, no stages) that would wipe prior SoT.
  TruSleepSequenceSession? _bestUsableSequenceForWindow(
    SleepSessionSummary file,
    List<TruSleepSequenceSession> sequences,
  ) {
    final best = _bestSequenceForWindow(file, sequences);
    if (best == null || !_sequenceHasUsableDetail(best)) return null;
    return best;
  }

  bool _sequenceHasUsableDetail(TruSleepSequenceSession s) {
    if (s.productStages.isNotEmpty) return true;
    if (s.sleepScore != null && s.sleepScore! > 0) return true;
    if (s.avgHrv != null ||
        s.avgHeartRate != null ||
        s.avgBreathRate != null ||
        s.avgOxygenSaturation != null) {
      return true;
    }
    return false;
  }

  List<SleepStageSummary> _priorStagesForWindow(
    SleepSessionSummary file,
    List<SleepSessionSummary> replaced,
    Map<String, List<SleepStageSummary>> priorByKey,
  ) {
    SleepSessionSummary? best;
    var bestOverlap = 0;
    for (final r in replaced) {
      final o = _overlapSec(file, r);
      if (o > bestOverlap) {
        bestOverlap = o;
        best = r;
      }
    }
    if (best == null || bestOverlap <= 0) return const [];
    return priorByKey[best.mergeKey] ?? const [];
  }

  Future<void> _attachMessageStagesOntoFileSot(
    List<SleepSessionSummary> messages,
  ) async {
    if (!_gateStillPassed() || messages.isEmpty) return;
    final existing = await _safeLoadSleep();
    if (existing.isEmpty || !_gateStillPassed()) return;
    final hasAnyStages = messages.any((m) => m.stages.isNotEmpty);
    if (!hasAnyStages) return;

    final updated = <SleepSessionSummary>[];
    for (final file in existing) {
      final stages = _stagesForFileWindow(file, messages);
      if (stages.isEmpty) continue;
      updated.add(
        SleepSessionSummary(
          beginUnix: file.beginUnix,
          endUnix: file.endUnix,
          wireType: file.wireType,
          stages: stages,
        ),
      );
    }
    if (updated.isEmpty) return;
    await _deleteStageFiles(updated);
    await _persistSleepStages(updated);
  }

  Future<void> _migrateFeelOnWake({
    required List<SleepSessionSummary> fromSessions,
    required List<SleepSessionSummary> toSessions,
  }) async {
    if (fromSessions.isEmpty || toSessions.isEmpty) return;
    final map = _feelOnWakeMap();
    if (map.isEmpty) return;
    final next = Map<String, dynamic>.from(map);
    var changed = false;
    for (final old in fromSessions) {
      final feel = map[old.mergeKey];
      if (feel == null) continue;
      SleepSessionSummary? best;
      var bestOverlap = 0;
      for (final n in toSessions) {
        final o = _overlapSec(old, n);
        if (o > bestOverlap) {
          bestOverlap = o;
          best = n;
        }
      }
      // No overlap → leave prior feel key untouched (retained nights).
      if (best == null || bestOverlap <= 0) continue;
      if (best.mergeKey == old.mergeKey) continue;
      next.remove(old.mergeKey);
      next[best.mergeKey] = feel;
      changed = true;
    }
    if (!changed || !_gateStillPassed()) return;
    await _prefs.setString(GateAPrefs.sleepFeelOnWakeJson, jsonEncode(next));
  }

  int _overlapSec(SleepSessionSummary a, SleepSessionSummary b) {
    final begin = a.beginUnix > b.beginUnix ? a.beginUnix : b.beginUnix;
    final end = a.endUnix < b.endUnix ? a.endUnix : b.endUnix;
    final o = end - begin;
    return o > 0 ? o : 0;
  }

  Future<void> _rewriteEnrichForFileSessions(
    List<SleepSessionSummary> fileSessions,
    List<SleepEnrichOutcome> enrich, {
    List<SleepSessionSummary> replaced = const [],
  }) async {
    if (!_gateStillPassed() || fileSessions.isEmpty) return;
    SleepEnrichOutcome? present;
    for (final o in enrich) {
      if (o.present) {
        present = o;
        break;
      }
    }
    if (present == null) return;
    final sequences = present.sequenceSessions;
    for (final session in fileSessions) {
      if (!_gateStillPassed()) return;
      final seq = _bestUsableSequenceForWindow(session, sequences);
      Map<String, dynamic>? priorSummary;
      if (seq == null && replaced.isNotEmpty) {
        priorSummary = await _priorTruSleepSummaryMap(session, replaced);
      }
      await persistSleepEnrich(
        session: session,
        present: true,
        refs: {
          'files': present.refs.map((r) => r.toJson()).toList(),
          if (present.stateIntervals.isNotEmpty)
            'stateIntervals':
                present.stateIntervals.map((i) => i.toJson()).toList(),
          if (seq != null)
            'trusleepSummary': seq.toSummaryJson()
          else if (priorSummary != null)
            'trusleepSummary': priorSummary,
        },
      );
    }
  }

  Future<Map<String, dynamic>?> _priorTruSleepSummaryMap(
    SleepSessionSummary file,
    List<SleepSessionSummary> replaced,
  ) async {
    SleepSessionSummary? best;
    var bestOverlap = 0;
    for (final r in replaced) {
      final o = _overlapSec(file, r);
      if (o > bestOverlap) {
        bestOverlap = o;
        best = r;
      }
    }
    if (best == null || bestOverlap <= 0) return null;
    final prior = await loadTruSleepSummary(best);
    return prior?.toSummaryJson();
  }

  Future<void> _mergeSleepEnrich(List<SleepEnrichOutcome> outcomes) async {
    if (!_gateStillPassed() || outcomes.isEmpty) return;
    for (final outcome in outcomes) {
      if (!_gateStillPassed()) return;
      if (!outcome.present) continue;
      if (outcome.beginUnix <= 0 || outcome.endUnix <= outcome.beginUnix) {
        continue;
      }
      final seq =
          _bestUsableSequenceForWindow(outcome.asSession, outcome.sequenceSessions);
      await persistSleepEnrich(
        session: outcome.asSession,
        present: true,
        refs: {
          'files': outcome.refs.map((r) => r.toJson()).toList(),
          if (outcome.stateIntervals.isNotEmpty)
            'stateIntervals':
                outcome.stateIntervals.map((i) => i.toJson()).toList(),
          if (seq != null) 'trusleepSummary': seq.toSummaryJson(),
        },
      );
    }
  }

  Future<void> _mergeSleep(List<SleepSessionSummary> incoming) async {
    if (!_gateStillPassed()) return;
    final valid = incoming
        .where((s) => s.beginUnix > 0 && s.endUnix > s.beginUnix)
        .toList();
    if (valid.isEmpty) return;

    final byKey = <String, SleepSessionSummary>{
      for (final s in valid) _sleepKey(s): s,
    };
    final unique = byKey.values.toList()
      ..sort((a, b) => b.beginUnix.compareTo(a.beginUnix));
    final existing = await _safeLoadSleep();
    if (!_gateStillPassed()) return;
    await _prefs.setString(
      GateAPrefs.sleepSessionsJson,
      jsonEncode(unique.map((s) => s.toJson()).toList()),
    );
    await _deleteStageFiles(existing);
    await _wipeSleepStagesDir();
    await _persistSleepStages(
      unique.where((s) => s.stages.isNotEmpty).toList(),
    );
  }

  String _sleepKey(SleepSessionSummary s) => s.mergeKey;

  bool _sleepOverlaps(SleepSessionSummary a, SleepSessionSummary b) {
    return a.beginUnix < b.endUnix && b.beginUnix < a.endUnix;
  }

  /// Replace-by-local-day across the completed FitnessTotals payload.
  /// Keeps prior rows for days not in the incoming set (incl. all-zero rows).
  Future<void> _mergeFitnessTotals(List<FitnessTotalsDay> incoming) async {
    if (!_gateStillPassed()) return;
    final valid = incoming.where((d) => d.dayKey.isNotEmpty).toList();
    if (valid.isEmpty) return;

    final existing = await _safeLoadFitnessTotals();
    final map = <String, FitnessTotalsDay>{
      for (final d in existing) d.dayKey: d,
      for (final d in valid) d.dayKey: d,
    };
    final merged = map.values.toList()
      ..sort((a, b) => b.dayKey.compareTo(a.dayKey));
    if (!_gateStillPassed()) return;
    await _prefs.setString(
      GateAPrefs.fitnessTotalsDayJson,
      jsonEncode(merged.map((d) => d.toJson()).toList()),
    );
  }

  @override
  Future<void> clearLocal() async {
    await _prefs.remove(GateAPrefs.sleepSessionsJson);
    await _prefs.remove(GateAPrefs.dailyHrJson);
    await _prefs.remove(GateAPrefs.fitnessTotalsDayJson);
    await _prefs.remove(GateAPrefs.lastAutoTrackingEnableJson);
    await _prefs.remove(GateAPrefs.sleepFeelOnWakeJson);
    await _prefs.remove(GateAPrefs.lastActivitySyncCursor);
    await _prefs.remove(GateAPrefs.activitySyncImplVersion);
    await _prefs.remove(GateAPrefs.fileSleepSotActive);
    _sleepLoadFailed = false;
    _hrLoadFailed = false;
    _fitnessTotalsLoadFailed = false;
    await _wipeSideFiles();
  }

  Future<void> _wipeSideFiles() async {
    final root = await _sideFileRoot();
    if (root == null) return;
    for (final rel in [
      GateAPrefs.dailyHrSeriesDir,
      GateAPrefs.sleepStagesDir,
      GateAPrefs.sleepEnrichDir,
      GateAPrefs.sleepFilesDir,
    ]) {
      final dir = Directory('${root.path}/$rel');
      try {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {
        // Best-effort wipe.
      }
    }
  }

  Future<void> _persistSleepStages(List<SleepSessionSummary> sessions) async {
    if (!_gateStillPassed()) return;
    final root = await _sideFileRoot();
    if (root == null) return;
    final dir = Directory('${root.path}/${GateAPrefs.sleepStagesDir}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    for (final session in sessions) {
      if (!_gateStillPassed()) return;
      if (session.stages.isEmpty) continue;
      final file = File(_stagesFilePath(root, session));
      await file.writeAsString(
        jsonEncode({
          'beginUnix': session.beginUnix,
          'endUnix': session.endUnix,
          'wireType': session.wireType,
          'stages': session.stages.map((s) => s.toJson()).toList(),
        }),
      );
    }
  }

  Future<void> _deleteStageFiles(List<SleepSessionSummary> sessions) async {
    final root = await _sideFileRoot();
    if (root == null) return;
    for (final session in sessions) {
      final file = File(_stagesFilePath(root, session));
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _wipeSleepStagesDir() async {
    final root = await _sideFileRoot();
    if (root == null) return;
    final dir = Directory('${root.path}/${GateAPrefs.sleepStagesDir}');
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Persist enrich outcome for a session (U6). Public for Sync merge path.
  Future<void> persistSleepEnrich({
    required SleepSessionSummary session,
    required bool present,
    Map<String, Object?>? refs,
  }) async {
    if (!_gateStillPassed()) return;
    final root = await _sideFileRoot();
    if (root == null) return;
    final dir = Directory('${root.path}/${GateAPrefs.sleepEnrichDir}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(_enrichFilePath(root, session));
    await file.writeAsString(
      jsonEncode({
        'beginUnix': session.beginUnix,
        'endUnix': session.endUnix,
        'present': present,
        if (refs != null) 'refs': refs,
      }),
    );
  }

  Map<String, dynamic> _feelOnWakeMap() {
    final raw = _prefs.getString(GateAPrefs.sleepFeelOnWakeJson);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  String _seriesFilePath(Directory root, String dayKey) =>
      '${root.path}/${GateAPrefs.dailyHrSeriesDir}/$dayKey.json';

  String _stagesFilePath(Directory root, SleepSessionSummary session) =>
      '${root.path}/${GateAPrefs.sleepStagesDir}/${_safeFileToken(session.mergeKey)}.json';

  String _enrichFilePath(Directory root, SleepSessionSummary session) =>
      '${root.path}/${GateAPrefs.sleepEnrichDir}/${_safeFileToken(session.mergeKey)}.json';

  String _safeFileToken(String key) =>
      key.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');

  Future<Directory?> _sideFileRoot() async {
    final override = _sideFileRootOverride?.call();
    if (override != null) return override;
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<List<SleepSessionSummary>> _safeLoadSleep() async {
    try {
      return await loadSleepSessions();
    } catch (_) {
      return const [];
    }
  }

  Future<List<DailyHrDaySummary>> _safeLoadHr() async {
    try {
      return await loadDailyHr();
    } catch (_) {
      return const [];
    }
  }

  Future<List<FitnessTotalsDay>> _safeLoadFitnessTotals() async {
    try {
      return await loadFitnessTotals();
    } catch (_) {
      return const [];
    }
  }
}

class _SleepMergeResult {
  const _SleepMergeResult({
    this.fileSotUpserted = false,
    this.maxUpsertedEndUnix = 0,
  });

  final bool fileSotUpserted;
  final int maxUpsertedEndUnix;
}
