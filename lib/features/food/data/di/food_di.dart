import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/food/data/food_meal_store.dart';

/// Registers FoodMealStore as a singleton.
///
/// Does NOT set onForgetWipeExtras alone — diagnostics_di composes the
/// last-writer wipe body to avoid overwrite hazard.
void initFoodDependencies(GetIt sl) {
  if (sl.isRegistered<FoodMealStore>()) return;

  sl.registerLazySingleton<FoodMealStore>(
    () => FoodMealStore(prefs: sl<SharedPreferences>()),
  );
}
