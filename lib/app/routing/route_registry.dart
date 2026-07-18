import 'package:fitness_os/features/device_pairing/presentation/view/device_pairing_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_route.dart';

/// Central place to register all feature routes
class RouteRegistry {
  static void registerAll() {
    DevicePairingRoute.register();
    WorkoutHistoryRoute.register();
    // [routes]
  }
}
