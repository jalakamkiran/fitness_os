import 'package:get_it/get_it.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync_di.dart';
import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/features/device_pairing/data/di/device_pairing_di.dart';
import 'package:fitness_os/features/home/data/di/home_di.dart';
import 'package:fitness_os/features/vitals/data/di/vitals_di.dart';
import 'package:fitness_os/features/workout_history/data/di/workout_history_di.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // Core dependencies (e.g., network client, local storage)
  // _initCore();

  if (!sl.isRegistered<StoreInvalidation>()) {
    sl.registerSingleton<StoreInvalidation>(StoreInvalidation());
  }

  await _initDevicePairing();
  await _initWorkoutHistory();
  await _initVitals();
  registerOneShotAutoSync(sl);
  _initHome();
  // [features] — auto-managed by create_feature.sh, do not edit manually
}

Future<void> _initDevicePairing() => initDevicePairingDependencies(sl);

Future<void> _initWorkoutHistory() => initWorkoutHistoryDependencies(sl);

Future<void> _initVitals() => initVitalsDependencies(sl);

void _initHome() => initHomeDependencies(sl);
