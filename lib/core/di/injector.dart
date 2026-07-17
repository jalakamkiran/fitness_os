import 'package:get_it/get_it.dart';
import 'package:fitness_os/features/home/data/di/home_di.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // Core dependencies (e.g., network client, local storage)
  // _initCore();

    _initHome();
  // [features] — auto-managed by create_feature.sh, do not edit manually
}

void _initHome() => initHomeDependencies(sl);
