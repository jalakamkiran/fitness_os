import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:fitness_os/core/backend/backend_config.dart';
import 'package:fitness_os/core/feature_flags.dart';
import 'package:fitness_os/features/lift/data/lift_store.dart';
import 'package:fitness_os/features/lift/domain/strength_set.dart';

class LiftSyncService {
  LiftSyncService({
    required LiftStore store,
    Dio? dio,
    @visibleForTesting this.debugForceSync = false,
  })  : _store = store,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: BackendConfig.baseUrl,
                headers: BackendConfig.isEnabled
                    ? {'Authorization': 'Bearer ${BackendConfig.writeKey}'}
                    : null,
              ),
            );

  final LiftStore _store;
  final Dio _dio;
  final bool debugForceSync;

  Future<int> syncPending() async {
    if (!debugForceSync &&
        (!FeatureFlags.liftWatch || !BackendConfig.isEnabled)) {
      return 0;
    }
    final pending = await _store.loadPendingUploadIds();
    if (pending.isEmpty) return 0;
    final sets = await _store.loadStrengthSets();
    final batch = sets.where((s) => pending.contains(s.id)).toList();
    if (batch.isEmpty) return 0;

    final body = {
      'sets': batch.map(_toBackend).toList(),
    };
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/v1/lift/strength-sets',
      data: body,
    );
    if (resp.statusCode == 200) {
      final synced = batch.map((s) => s.id);
      await _store.removePendingUploads(synced);
      return batch.length;
    }
    return 0;
  }

  Map<String, dynamic> _toBackend(StrengthSet s) => {
        'id': s.id,
        'sessionId': s.sessionId,
        'exerciseId': s.exerciseId,
        'exercise': s.exercise,
        'setIndex': s.setIndex,
        'plannedKg': s.plannedKg,
        'plannedReps': s.plannedReps,
        'actualKg': s.actualKg,
        'actualReps': s.actualReps,
        'failed': s.failed,
        'replyText': s.replyText,
        'unknownReply': s.unknownReply,
        'notifiedAtMs': s.notifiedAtMs,
        'loggedAtMs': s.loggedAtMs,
        'source': s.source,
        'workoutId': s.workoutNumber != null ? 'workout_${s.workoutNumber}' : null,
      };
}