import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/food/data/food_day_export_service.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/data/food_notification_scheduler.dart';

/// Registers FoodMealStore, FoodNotificationScheduler, and FoodDayExportService as singletons.
///
/// Does NOT set onForgetWipeExtras alone — diagnostics_di composes the
/// last-writer wipe body to avoid overwrite hazard.
void initFoodDependencies(GetIt sl) {
  if (sl.isRegistered<FoodMealStore>()) return;

  final store = FoodMealStore(prefs: sl<SharedPreferences>());
  sl.registerLazySingleton<FoodMealStore>(() => store);

  sl.registerLazySingleton<FoodNotificationScheduler>(
    () => FoodNotificationScheduler(
      prefs: sl<SharedPreferences>(),
      store: store,
    ),
  );

  sl.registerLazySingleton<FoodDayExportService>(
    () {
      final pairing = sl<DevicePairingRepository>();
      return FoodDayExportService(
        store: store,
        isForgetInFlight: () => pairing is DevicePairingRepositoryImpl
            ? pairing.forgetInFlight
            : false,
      );
    },
  );
}
