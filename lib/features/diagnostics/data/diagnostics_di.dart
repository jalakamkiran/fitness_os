import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_service.dart';
import 'package:fitness_os/features/food/data/food_day_export_service.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/data/food_notification_scheduler.dart';
import 'package:fitness_os/features/food/domain/food_capture_intent.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/data/strength_session_export_service.dart';
import 'package:fitness_os/features/workout_history/data/swim_reasoner_service.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';

/// Registers export service and composes Forget wipe/busy with vitals + food +
/// workouts.
///
/// Call **after** [initVitalsDependencies], [initFoodDependencies], and
/// [initWorkoutHistoryDependencies] so wipe extras compose rather than overwrite.
///
/// Last-writer composition: vitals clear → app export prune → food clear →
/// food export prune → workout clearLocal → strength export prune →
/// share_plus prune → cancel notifs.
/// DO NOT assign onForgetWipeExtras from food_di or workout_history_di;
/// this is the only site.
Future<void> initDiagnosticsDependencies(GetIt sl) async {
  if (sl.isRegistered<AppDataExportService>()) return;

  sl.registerLazySingleton<AppDataExportService>(
    () {
      final pairing = sl<DevicePairingRepository>();
      return AppDataExportService(
        prefs: sl<SharedPreferences>(),
        isSyncInFlight: () => sl<HuaweiLink>().syncInFlight,
        isVitalsSyncOrMergeInFlight: () =>
            sl<VitalsRepository>().isSyncOrMergeInFlight,
        isForgetInFlight: () => pairing is DevicePairingRepositoryImpl
            ? pairing.forgetInFlight
            : false,
        isWorkoutSyncOrMergeInFlight: () =>
            sl.isRegistered<WorkoutHistoryRepository>()
                ? sl<WorkoutHistoryRepository>().isSyncOrMergeInFlight
                : false,
        isStrengthExportInFlight: () =>
            sl.isRegistered<StrengthSessionExportService>()
                ? sl<StrengthSessionExportService>().exportInFlight
                : false,
        isQwenInstalled: () => sl<SwimReasonerService>().qwen3.isInstalled(),
      );
    },
  );

  final pairing = sl<DevicePairingRepository>();
  if (pairing is DevicePairingRepositoryImpl) {
    final vitals = sl<VitalsRepository>();
    final export = sl<AppDataExportService>();
    final foodStore =
        sl.isRegistered<FoodMealStore>() ? sl<FoodMealStore>() : null;
    final foodScheduler = sl.isRegistered<FoodNotificationScheduler>()
        ? sl<FoodNotificationScheduler>()
        : null;
    final foodExport = sl.isRegistered<FoodDayExportService>()
        ? sl<FoodDayExportService>()
        : null;
    final workouts = sl.isRegistered<WorkoutHistoryRepository>()
        ? sl<WorkoutHistoryRepository>()
        : null;
    final strengthExport = sl.isRegistered<StrengthSessionExportService>()
        ? sl<StrengthSessionExportService>()
        : null;

    // Last-writer composition — optional stores must not silently overwrite
    // the vitals/food wipe body when workout DI is missing.
    pairing.onForgetWipeExtras = () async {
      await vitals.clearLocal();
      await export.pruneExportCache();
      if (foodStore != null) {
        await foodStore.clearLocal();
      }
      if (foodExport != null) {
        await foodExport.pruneFoodExportCache();
      }
      if (workouts != null) {
        await workouts.clearLocal();
      }
      if (strengthExport != null) {
        await strengthExport.pruneStrengthExportCache();
      }
      // Explicit share_plus prune even if app-data prune were skipped.
      await pruneSharePlusCache();
      if (foodScheduler != null) {
        await foodScheduler.cancelAll();
        FoodCaptureIntent.clearPending();
      }
    };

    pairing.isForgetBlocked = () =>
        vitals.isSyncOrMergeInFlight ||
        export.exportInFlight ||
        (foodExport?.exportInFlight ?? false) ||
        (strengthExport?.exportInFlight ?? false) ||
        (workouts?.isSyncOrMergeInFlight ?? false);
  }
}

/// Removes `getTemporaryDirectory()/share_plus` residue (Forget wipe).
Future<void> pruneSharePlusCache() async {
  try {
    final temp = await getTemporaryDirectory();
    final shareCache = Directory('${temp.path}/share_plus');
    if (await shareCache.exists()) {
      await shareCache.delete(recursive: true);
    }
  } catch (_) {
    // Best-effort prune.
  }
}
