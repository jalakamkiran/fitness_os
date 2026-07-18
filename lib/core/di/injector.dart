import 'package:get_it/get_it.dart';
import 'package:fitness_os/features/device_pairing/data/di/device_pairing_di.dart';
import 'package:fitness_os/features/workout_history/data/di/workout_history_di.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // Core dependencies (e.g., network client, local storage)
  // _initCore();

  await _initDevicePairing();
  await _initWorkoutHistory();
  // [features] — auto-managed by create_feature.sh, do not edit manually
}

Future<void> _initDevicePairing() => initDevicePairingDependencies(sl);

Future<void> _initWorkoutHistory() => initWorkoutHistoryDependencies(sl);
