import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/domain/sleep_hr_window.dart';
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
      final result = await _link.syncActivity(
        skipTruSleepSoft: last?.outcomeFor('trusleep') == 'armed',
        skipAutoHrSoft: last?.outcomeFor('auto_hr') == 'armed',
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
          await _mergeContainers(result);
          final sleep = await _safeLoadSleep();
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
        return 'Wear the watch for several hours, then Sync — '
            'fresh auto-HR may not backfill older minutes';
      }
      if (hrOutcome == 'skipped' ||
          hrOutcome == 'failed' ||
          hrOutcome == 'timed_out') {
        return 'Auto-HR not armed — tap Enable auto-tracking, then wear and Sync';
      }
      if (lastEnable == null) {
        return 'Tap Enable auto-tracking, wear several hours, then Sync';
      }
    }
    if (lastEnable == null && enableSkipped) {
      return 'Enable skipped — watch may need TruSleep / auto-HR armed';
    }
    return 'No new sleep or heart-rate data in range';
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

  Future<void> _mergeContainers(ActivitySyncResult result) async {
    if (!_gateStillPassed()) return;
    final completed = result.completedContainers;
    if (completed.contains('sleep') && !_sleepLoadFailed) {
      await _mergeSleep(result.sleepSessions);
    }
    if (!_gateStillPassed()) return;
    if (completed.contains('daily_hr') &&
        result.dailyHrSamples.isNotEmpty &&
        !_hrLoadFailed) {
      await _mergeDailyHr(result.dailyHrSamples);
    }
    if (!_gateStillPassed()) return;
    // FitnessTotals: merge even all-zero scalar rows (do not copy HR samples guard).
    if (completed.contains('fitness_totals') && !_fitnessTotalsLoadFailed) {
      await _mergeFitnessTotals(result.fitnessTotals);
    }
  }

  Future<void> _mergeSleep(List<SleepSessionSummary> incoming) async {
    if (!_gateStillPassed()) return;
    final valid = incoming
        .where((s) => s.beginUnix > 0 && s.endUnix > s.beginUnix)
        .toList();
    if (valid.isEmpty) return;

    final existing = await _safeLoadSleep();
    // Re-sync replaces overlapping fragments (old per-page splits, etc.).
    final replaced = existing.where((e) {
      return valid.any((i) => _sleepOverlaps(e, i));
    }).toList();
    final kept = existing.where((e) {
      return !valid.any((i) => _sleepOverlaps(e, i));
    }).toList();
    final byKey = <String, SleepSessionSummary>{
      for (final s in kept) _sleepKey(s): s,
      for (final s in valid) _sleepKey(s): s,
    };
    final merged = byKey.values.toList()
      ..sort((a, b) => b.beginUnix.compareTo(a.beginUnix));
    if (!_gateStillPassed()) return;
    await _prefs.setString(
      GateAPrefs.sleepSessionsJson,
      jsonEncode(merged.map((s) => s.toJson()).toList()),
    );
    await _deleteStageFiles(replaced);
    await _persistSleepStages(valid);
  }

  String _sleepKey(SleepSessionSummary s) => s.mergeKey;

  bool _sleepOverlaps(SleepSessionSummary a, SleepSessionSummary b) {
    return a.beginUnix < b.endUnix && b.beginUnix < a.endUnix;
  }

  Future<void> _mergeDailyHr(List<DailyHrSample> samples) async {
    if (!_gateStillPassed()) return;
    final byDay = <String, List<int>>{};
    final byDaySamples = <String, List<DailyHrSample>>{};
    for (final s in samples) {
      if (s.bpm <= 0 || s.timestampUnix <= 0) continue;
      final day = _localDayKey(s.timestampUnix);
      byDay.putIfAbsent(day, () => []).add(s.bpm);
      byDaySamples.putIfAbsent(day, () => []).add(s);
    }
    if (byDay.isEmpty) return;

    final existing = await _safeLoadHr();
    final map = <String, DailyHrDaySummary>{
      for (final d in existing) d.dayKey: d,
    };
    for (final entry in byDay.entries) {
      final bpms = entry.value;
      final minBpm = bpms.reduce((a, b) => a < b ? a : b);
      final maxBpm = bpms.reduce((a, b) => a > b ? a : b);
      final avg = (bpms.reduce((a, b) => a + b) / bpms.length).round();
      map[entry.key] = DailyHrDaySummary(
        dayKey: entry.key,
        minBpm: minBpm,
        avgBpm: avg,
        maxBpm: maxBpm,
        sampleCount: bpms.length,
      );
    }
    final merged = map.values.toList()
      ..sort((a, b) => b.dayKey.compareTo(a.dayKey));
    if (!_gateStillPassed()) return;
    await _prefs.setString(
      GateAPrefs.dailyHrJson,
      jsonEncode(merged.map((d) => d.toJson()).toList()),
    );
    await _persistDailyHrSeries(byDaySamples);
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

  Future<void> _persistDailyHrSeries(
    Map<String, List<DailyHrSample>> incomingByDay,
  ) async {
    if (!_gateStillPassed()) return;
    final root = await _sideFileRoot();
    if (root == null) return;
    final seriesDir = Directory('${root.path}/${GateAPrefs.dailyHrSeriesDir}');
    if (!await seriesDir.exists()) {
      await seriesDir.create(recursive: true);
    }
    for (final entry in incomingByDay.entries) {
      if (!_gateStillPassed()) return;
      final existing = await loadDailyHrSeries(entry.key);
      final byTs = <int, DailyHrSample>{
        for (final s in existing) s.timestampUnix: s,
        for (final s in entry.value) s.timestampUnix: s,
      };
      final merged = byTs.values.toList()
        ..sort((a, b) => a.timestampUnix.compareTo(b.timestampUnix));
      final file = File(_seriesFilePath(root, entry.key));
      await file.writeAsString(
        jsonEncode({
          'dayKey': entry.key,
          'samples': merged.map((s) => s.toJson()).toList(),
        }),
      );
    }
  }

  @override
  Future<void> clearLocal() async {
    await _prefs.remove(GateAPrefs.sleepSessionsJson);
    await _prefs.remove(GateAPrefs.dailyHrJson);
    await _prefs.remove(GateAPrefs.fitnessTotalsDayJson);
    await _prefs.remove(GateAPrefs.lastAutoTrackingEnableJson);
    await _prefs.remove(GateAPrefs.sleepFeelOnWakeJson);
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

  String _localDayKey(int unixSec) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
