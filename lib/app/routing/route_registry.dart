import 'package:fitness_os/app/shell/app_shell_route.dart';
import 'package:fitness_os/features/device_pairing/presentation/view/device_pairing_route.dart';
import 'package:fitness_os/features/food/presentation/view/food_capture_route.dart';
import 'package:fitness_os/features/food/presentation/view/food_meal_edit_route.dart';
import 'package:fitness_os/features/home/presentation/view/home_route.dart';
import 'package:fitness_os/features/vitals/presentation/view/recovery_tab_host.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_detail_route.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_history_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/coach_settings_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_screen.dart';

/// Central place to register all feature routes
class RouteRegistry {
  static void registerAll() {
    AppShellRoute.register(
      vitalsBody: const RecoveryTabHost(),
      workoutsBody: const WorkoutHistoryScreen(),
    );
    DevicePairingRoute.register();
    WorkoutHistoryRoute.register();
    WorkoutDetailRoute.register();
    SleepDetailRoute.register();
    SleepHistoryRoute.register();
    CoachSettingsRoute.register();
    FoodCaptureRoute.register();
    FoodMealEditRoute.register();
    HomeRoute.register();
  }
}
