import 'package:get_it/get_it.dart';
import 'package:fitness_os/features/device_pairing/data/di/device_pairing_di.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // Core dependencies (e.g., network client, local storage)
  // _initCore();

  await _initDevicePairing();
  // [features] — auto-managed by create_feature.sh, do not edit manually
}

Future<void> _initDevicePairing() => initDevicePairingDependencies(sl);
