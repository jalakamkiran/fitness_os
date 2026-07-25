import 'package:fitness_os/app/shell/app_shell_route.dart';
import 'package:fitness_os/features/device_pairing/presentation/view/device_pairing_route.dart';
import 'package:fitness_os/features/vitals/presentation/view/vitals_screen.dart';
import 'package:fitness_os/features/workout_history/presentation/view/coach_settings_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_route.dart';

/// Central place to register all feature routes
class RouteRegistry {
  static void registerAll() {
    AppShellRoute.register(vitalsBody: const VitalsScreen());
    DevicePairingRoute.register();
    WorkoutHistoryRoute.register();
    WorkoutDetailRoute.register();
    CoachSettingsRoute.register();
    // [routes] — vitals is tab-hosted (no public /vitals route)
  }
}
