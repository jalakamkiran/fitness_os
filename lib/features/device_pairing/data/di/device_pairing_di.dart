import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/feature_flags.dart';
import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_bloc.dart';

Future<void> initDevicePairingDependencies(GetIt sl) async {
  final prefs = await SharedPreferences.getInstance();
  if (!sl.isRegistered<SharedPreferences>()) {
    sl.registerSingleton<SharedPreferences>(prefs);
  }

  if (!sl.isRegistered<HuaweiBtChannel>()) {
    sl.registerLazySingleton<HuaweiBtChannel>(() => HuaweiBtChannel());
  }
  if (FeatureFlags.liftWatch) {
    await sl<HuaweiBtChannel>().liftSetBuildFlag(enabled: true);
  }
  sl.registerLazySingleton<HuaweiLink>(
    () => HuaweiLink(channel: sl<HuaweiBtChannel>()),
  );

  sl.registerLazySingleton<DevicePairingRepository>(
    () => DevicePairingRepositoryImpl(
      link: sl(),
      prefs: sl(),
    ),
  );

  sl.registerFactory(
    () => DevicePairingBloc(repository: sl()),
  );
}
