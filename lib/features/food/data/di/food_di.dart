import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/data/food_notification_scheduler.dart';

/// Registers FoodMealStore and FoodNotificationScheduler as singletons.
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
}
