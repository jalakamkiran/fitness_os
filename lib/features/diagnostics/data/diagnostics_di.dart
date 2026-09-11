import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_service.dart';
import 'package:fitness_os/features/diagnostics/data/run_session_export_service.dart';
import 'package:fitness_os/features/food/data/food_day_export_service.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/data/food_notification_scheduler.dart';
import 'package:fitness_os/features/food/domain/food_capture_intent.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/data/swim_reasoner_service.dart';

/// Registers export service and composes Forget wipe/busy with vitals + food.
///
/// Call **after** [initVitalsDependencies] and [initFoodDependencies] so wipe
/// extras compose rather than overwrite.
///
/// Last-writer composition pattern: vitals clear → app export prune → food clear
/// → food export prune → cancel notifs → run session store clear → run export prune.
/// DO NOT assign onForgetWipeExtras from food_di alone; this is the only site.
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
        isQwenInstalled: () => sl<SwimReasonerService>().qwen3.isInstalled(),
      );
    },
  );

  if (!sl.isRegistered<RunSessionExportService>()) {
    sl.registerLazySingleton<RunSessionExportService>(
      () {
        final pairing = sl<DevicePairingRepository>();
        final foodExport = sl.isRegistered<FoodDayExportService>()
            ? sl<FoodDayExportService>()
            : null;
        return RunSessionExportService(
          prefs: sl<SharedPreferences>(),
          runSessionStore: sl<RunSessionStore>(),
          isSyncInFlight: () => sl<HuaweiLink>().syncInFlight,
          isForgetInFlight: () => pairing is DevicePairingRepositoryImpl
              ? pairing.forgetInFlight
              : false,
          isAppExportInFlight: () => sl<AppDataExportService>().exportInFlight,
          isFoodExportInFlight: () => foodExport?.exportInFlight ?? false,
        );
      },
    );
  }

  final pairing = sl<DevicePairingRepository>();
  if (pairing is DevicePairingRepositoryImpl) {
    final vitals = sl<VitalsRepository>();
    final export = sl<AppDataExportService>();
    final runExport = sl<RunSessionExportService>();
    final runStore =
        sl.isRegistered<RunSessionStore>() ? sl<RunSessionStore>() : null;
    final foodStore =
        sl.isRegistered<FoodMealStore>() ? sl<FoodMealStore>() : null;
    final foodScheduler = sl.isRegistered<FoodNotificationScheduler>()
        ? sl<FoodNotificationScheduler>()
        : null;
    final foodExport = sl.isRegistered<FoodDayExportService>()
        ? sl<FoodDayExportService>()
        : null;

    // Last-writer composition: vitals → export → food → food export →
    // cancel notifs → run session clear → run export prune.
    pairing.onForgetWipeExtras = () async {
      await vitals.clearLocal();
      await export.pruneExportCache();
      if (foodStore != null) {
        await foodStore.clearLocal();
      }
      if (foodExport != null) {
        await foodExport.pruneFoodExportCache();
      }
      if (foodScheduler != null) {
        await foodScheduler.cancelAll();
        FoodCaptureIntent.clearPending();
      }
      if (runStore != null) {
        await runStore.clearLocal();
      }
      await runExport.pruneExportCache();
    };

    pairing.isForgetBlocked = () =>
        vitals.isSyncOrMergeInFlight ||
        export.exportInFlight ||
        (foodExport?.exportInFlight ?? false) ||
        runExport.exportInFlight;
  }
}
