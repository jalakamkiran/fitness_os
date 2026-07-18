import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
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
          if (_sleepLoadFailed || _hrLoadFailed) {
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
  }

  Future<void> _mergeSleep(List<SleepSessionSummary> incoming) async {
    if (!_gateStillPassed()) return;
    final valid = incoming
        .where((s) => s.beginUnix > 0 && s.endUnix > s.beginUnix)
        .toList();
    if (valid.isEmpty) return;

    final existing = await _safeLoadSleep();
    // Re-sync replaces overlapping fragments (old per-page splits, etc.).
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
  }

  String _sleepKey(SleepSessionSummary s) =>
      '${s.beginUnix}:${s.endUnix}:${s.wireType ?? ''}';

  bool _sleepOverlaps(SleepSessionSummary a, SleepSessionSummary b) {
    return a.beginUnix < b.endUnix && b.beginUnix < a.endUnix;
  }

  Future<void> _mergeDailyHr(List<DailyHrSample> samples) async {
    if (!_gateStillPassed()) return;
    final byDay = <String, List<int>>{};
    for (final s in samples) {
      if (s.bpm <= 0 || s.timestampUnix <= 0) continue;
      final day = _localDayKey(s.timestampUnix);
      byDay.putIfAbsent(day, () => []).add(s.bpm);
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

  @override
  Future<void> clearLocal() async {
    await _prefs.remove(GateAPrefs.sleepSessionsJson);
    await _prefs.remove(GateAPrefs.dailyHrJson);
    await _prefs.remove(GateAPrefs.lastAutoTrackingEnableJson);
    _sleepLoadFailed = false;
    _hrLoadFailed = false;
    await _wipeSideFiles();
  }

  Future<void> _wipeSideFiles() async {
    final root = _sideFileRootOverride?.call();
    if (root == null) return;
    try {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort wipe.
    }
  }
}
