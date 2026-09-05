import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_service.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/data/swim_reasoner_service.dart';

/// Registers export service and composes Forget wipe/busy with vitals + food.
///
/// Call **after** [initVitalsDependencies] and [initFoodDependencies] so wipe
/// extras compose rather than overwrite.
///
/// Last-writer composition pattern: vitals clear → app export prune → food clear.
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

  final pairing = sl<DevicePairingRepository>();
  if (pairing is DevicePairingRepositoryImpl) {
    final vitals = sl<VitalsRepository>();
    final export = sl<AppDataExportService>();
    final foodStore = sl.isRegistered<FoodMealStore>() ? sl<FoodMealStore>() : null;

    // Last-writer composition: vitals → export → food
    pairing.onForgetWipeExtras = () async {
      await vitals.clearLocal();
      await export.pruneExportCache();
      if (foodStore != null) {
        await foodStore.clearLocal();
      }
    };

    // TODO U6: OR foodExportInFlight into isForgetBlocked (stub false for now)
    pairing.isForgetBlocked =
        () => vitals.isSyncOrMergeInFlight || export.exportInFlight;
  }
}
