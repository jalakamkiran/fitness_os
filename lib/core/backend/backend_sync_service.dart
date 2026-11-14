import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fitness_os/core/backend/backend_config.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackendSyncService {
  BackendSyncService({
    required Dio dio,
    required SharedPreferences prefs,
    required WorkoutHistoryRepository workoutRepo,
    required VitalsRepository vitalsRepo,
  })  : _dio = dio,
        _prefs = prefs,
        _workoutRepo = workoutRepo,
        _vitalsRepo = vitalsRepo;

  final Dio _dio;
  final SharedPreferences _prefs;
  final WorkoutHistoryRepository _workoutRepo;
  final VitalsRepository _vitalsRepo;

  static const _lastSyncKey = 'backend_last_sync_ms';
  static const _syncIntervalMs = 5 * 60 * 1000; // 5 minutes

  bool _syncInProgress = false;

  bool get canSync => !_syncInProgress && BackendConfig.isEnabled;

  Future<void> syncToBackend() async {
    if (!canSync) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastSync = _prefs.getInt(_lastSyncKey) ?? 0;

    if (now - lastSync < _syncIntervalMs) {
      return;
    }

    _syncInProgress = true;
    try {
      final payload = await _buildSyncPayload();

      if (_isEmpty(payload)) {
        await _prefs.setInt(_lastSyncKey, now);
        return;
      }

      final response = await _dio.post(
        '/sync',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${BackendConfig.writeKey}',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        await _prefs.setInt(_lastSyncKey, now);
      }
    } catch (e) {
      // Fail silently - sync will retry on next app open
      print('Backend sync failed: $e');
    } finally {
      _syncInProgress = false;
    }
  }

  Future<Map<String, dynamic>> _buildSyncPayload() async {
    final payload = <String, dynamic>{};

    final workouts = await _workoutRepo.loadWorkouts();
    if (workouts.isNotEmpty) {
      payload['workouts'] = workouts
          .map((w) => {
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
                if (w.anaerobicEffect != null)
                  'anaerobicEffect': w.anaerobicEffect,
                if (w.recoveryTime != null) 'recoveryTime': w.recoveryTime,
              })
          .toList();
    }

    final sleepSessions = await _vitalsRepo.loadSleepSessions();
    if (sleepSessions.isNotEmpty) {
      payload['sleep'] = [];
      for (final session in sleepSessions) {
        final stages = await _vitalsRepo.loadSleepStages(session);
        final enrich = await _vitalsRepo.loadTruSleepSummary(session);

        payload['sleep'].add({
          'beginUnix': session.beginUnix,
          'endUnix': session.endUnix,
          if (stages.isNotEmpty)
            'stages': stages
                .map((s) => {
                      'timestampUnix': s.timestampUnix,
                      'durationMin': s.durationMin,
                      'stage': s.stage,
                    })
                .toList(),
          if (enrich != null) ...{
            if (enrich.sleepScore != null) 'sleepScore': enrich.sleepScore,
            if (enrich.avgHeartRate != null) 'avgHr': enrich.avgHeartRate,
            if (enrich.avgHrv != null) 'avgHrv': enrich.avgHrv,
            if (enrich.avgBreathRate != null)
              'avgBreathRate': enrich.avgBreathRate,
            if (enrich.avgOxygenSaturation != null)
              'avgSpO2': enrich.avgOxygenSaturation,
          },
        });
      }
    }

    final fitnessTotals = await _vitalsRepo.loadFitnessTotals();
    if (fitnessTotals.isNotEmpty) {
      payload['dailyTotals'] = fitnessTotals
          .map((t) => {
                'dayKey': t.dayKey,
                'totalKcal': t.calories,
                'steps': t.steps,
              })
          .toList();
    }

    final dailyHr = await _vitalsRepo.loadDailyHr();
    if (dailyHr.isNotEmpty) {
      payload['heartRate'] = dailyHr
          .map((hr) => {
                'dayKey': hr.dayKey,
                'avgHr': hr.avgBpm,
                'maxHr': hr.maxBpm,
              })
          .toList();
    }

    return payload;
  }

  bool _isEmpty(Map<String, dynamic> payload) {
    return payload.isEmpty ||
        payload.values.every((v) => v is List && (v as List).isEmpty);
  }
}
