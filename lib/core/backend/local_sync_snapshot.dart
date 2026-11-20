import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fitness_os/core/backend/canonical_json.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';

class LocalSyncSnapshot {
  LocalSyncSnapshot({
    required WorkoutHistoryRepository workouts,
    required VitalsRepository vitals,
    Duration pollInterval = const Duration(milliseconds: 250),
    Duration busyTimeout = const Duration(seconds: 15),
  })  : _workouts = workouts,
        _vitals = vitals,
        _pollInterval = pollInterval,
        _busyTimeout = busyTimeout;

  final WorkoutHistoryRepository _workouts;
  final VitalsRepository _vitals;
  final Duration _pollInterval;
  final Duration _busyTimeout;

  /// Null when repositories are still merging/syncing after [busyTimeout].
  Future<List<SyncRecord>?> build() async {
    final deadline = DateTime.now().add(_busyTimeout);
    while (_workouts.isSyncOrMergeInFlight || _vitals.isSyncOrMergeInFlight) {
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(_pollInterval);
    }

    final records = <SyncRecord>[];

    final workouts = await _workouts.loadLocal();
    for (final w in workouts) {
      final id = 'workout_${w.number}';
      final body = <String, dynamic>{
        'number': w.number,
        'type': w.type,
        'startTime': w.startTime,
        'endTime': w.endTime,
        'durationSec': w.durationSec,
        if (w.calories != null) 'calories': w.calories,
        if (w.distanceM != null) 'distanceM': w.distanceM,
        if (w.steps != null) 'steps': w.steps,
        if (w.hrMin != null) 'hrMin': w.hrMin,
        if (w.hrMax != null) 'hrMax': w.hrMax,
        if (w.laps != null) 'laps': w.laps,
        if (w.strokes != null) 'strokes': w.strokes,
        if (w.avgSwolf != null) 'avgSwolf': w.avgSwolf,
        if (w.poolLength != null) 'poolLength': w.poolLength,
        if (w.load != null) 'load': w.load,
        if (w.aerobicEffect != null) 'aerobicEffect': w.aerobicEffect,
        if (w.anaerobicEffect != null) 'anaerobicEffect': w.anaerobicEffect,
        if (w.recoveryTime != null) 'recoveryTime': w.recoveryTime,
        'clientId': id,
      };
      final hash = _hashBody(body);
      body['contentHash'] = hash;
      records.add(
        SyncRecord(
          kind: SyncRecordKind.workout,
          id: id,
          body: body,
          contentHash: hash,
        ),
      );
    }

    final sleepSessions = await _vitals.loadSleepSessions();
    for (final session in sleepSessions) {
      final id = 'sleep_${session.beginUnix}';
      final stages = await _vitals.loadSleepStages(session);
      final enrich = await _vitals.loadTruSleepSummary(session);
      final body = <String, dynamic>{
        'beginUnix': session.beginUnix,
        'endUnix': session.endUnix,
        'clientId': id,
      };
      if (stages.isNotEmpty) {
        body['stages'] = stages
            .where((s) => _backendStageCode(s.wireType) != null)
            .map((s) => {
                  'timestampUnix': s.timestampUnix,
                  'durationMin': s.durationMin,
                  'stage': _backendStageCode(s.wireType),
                })
            .toList();
      }
      if (enrich != null) {
        if (enrich.sleepScore != null) body['sleepScore'] = enrich.sleepScore;
        if (enrich.avgHeartRate != null) body['avgHr'] = enrich.avgHeartRate;
        if (enrich.avgHrv != null) body['avgHrv'] = enrich.avgHrv;
        if (enrich.avgBreathRate != null) {
          body['avgBreathRate'] = enrich.avgBreathRate;
        }
        if (enrich.avgOxygenSaturation != null) {
          body['avgSpO2'] = enrich.avgOxygenSaturation;
        }
      }
      final hash = _hashBody(body);
      body['contentHash'] = hash;
      records.add(
        SyncRecord(
          kind: SyncRecordKind.sleep,
          id: id,
          body: body,
          contentHash: hash,
        ),
      );
    }

    final fitnessTotals = await _vitals.loadFitnessTotals();
    for (final t in fitnessTotals) {
      final id = t.dayKey;
      final body = <String, dynamic>{
        'dayKey': t.dayKey,
        'totalKcal': t.calories,
        'steps': t.steps,
        'clientId': id,
      };
      final hash = _hashBody(body);
      body['contentHash'] = hash;
      records.add(
        SyncRecord(
          kind: SyncRecordKind.dailyTotals,
          id: id,
          body: body,
          contentHash: hash,
        ),
      );
    }

    final dailyHr = await _vitals.loadDailyHr();
    for (final hr in dailyHr) {
      final id = hr.dayKey;
      final body = <String, dynamic>{
        'dayKey': hr.dayKey,
        'avgHr': hr.avgBpm,
        'maxHr': hr.maxBpm,
        'clientId': id,
      };
      final hash = _hashBody(body);
      body['contentHash'] = hash;
      records.add(
        SyncRecord(
          kind: SyncRecordKind.heartRate,
          id: id,
          body: body,
          contentHash: hash,
        ),
      );
    }

    return records;
  }

  static String _hashBody(Map<String, dynamic> bodyWithoutContentHash) {
    return sha256
        .convert(utf8.encode(canonicalJson(bodyWithoutContentHash)))
        .toString();
  }

  static int? _backendStageCode(int? wireType) => switch (wireType) {
        1 => 2,
        2 => 3,
        3 => 4,
        4 || 7 => 1,
        _ => null,
      };
}