import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:fitness_os/core/backend/backend_sync_service.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';
import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';
import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';

/// Sequential auto-sync pass + optional post-watch backend push.
Future<void> runAutoSyncPass({
  required WorkoutHistoryRepository workouts,
  required VitalsRepository vitals,
  BackendPusher? pusher,
}) async {
  final pass = SentrySyncInstrumentation.startPassTransaction(
    trigger: 'auto',
  );
  var outcome = 'ok';
  try {
    await workouts.syncFromWatch();
    await vitals.syncFromWatch();
    await SentrySyncInstrumentation.finishWithStatus(pass, status: 'ok');
  } catch (_) {
    outcome = 'error';
    await SentrySyncInstrumentation.finishWithStatus(pass, status: 'error');
    rethrow;
  } finally {
    await SentrySyncInstrumentation.addBackendSyncBreadcrumb(
      'watch_synced',
      data: {'outcome': outcome},
    );
    if (pusher != null) {
      unawaited(pusher.push(SyncTrigger.postWatch));
      unawaited(
        SentrySyncInstrumentation.addBackendSyncBreadcrumb('post_watch_push'),
      );
    }
  }
}

/// Registers [OneShotAutoSync] after workout + vitals repos exist.
void registerOneShotAutoSync(GetIt sl) {
  if (sl.isRegistered<OneShotAutoSync>()) return;

  sl.registerLazySingleton<OneShotAutoSync>(() {
    final link = sl<HuaweiLink>();
    final workouts = sl<WorkoutHistoryRepository>();
    final vitals = sl<VitalsRepository>();
    return OneShotAutoSync(
      isSessionReady: () => isAutoSyncSessionReady(link.state),
      isSyncBusy: () =>
          link.syncInFlight || vitals.isSyncOrMergeInFlight,
      runPass: () => runAutoSyncPass(
        workouts: workouts,
        vitals: vitals,
        pusher: sl.isRegistered<BackendPusher>() ? sl<BackendPusher>() : null,
      ),
      onPassSettled: () => sl<StoreInvalidation>().notify(),
    );
  });
}