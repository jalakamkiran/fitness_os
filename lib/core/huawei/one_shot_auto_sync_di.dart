import 'package:get_it/get_it.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';
import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';

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
      runPass: () async {
        final pass = SentrySyncInstrumentation.startPassTransaction(
          trigger: 'auto',
        );
        try {
          // Sequential: shared Huawei Sync single-flight cannot overlap.
          await workouts.syncFromWatch();
          await vitals.syncFromWatch();
          await SentrySyncInstrumentation.finishWithStatus(
            pass,
            status: 'ok',
          );
        } catch (_) {
          await SentrySyncInstrumentation.finishWithStatus(
            pass,
            status: 'error',
          );
          rethrow;
        }
      },
    );
  });
}
