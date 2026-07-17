import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_bloc.dart';

Future<void> initDevicePairingDependencies(GetIt sl) async {
  final prefs = await SharedPreferences.getInstance();

  sl.registerLazySingleton<HuaweiLink>(() => HuaweiLink());

  sl.registerLazySingleton<DevicePairingRepository>(
    () => DevicePairingRepositoryImpl(
      link: sl(),
      prefs: prefs,
    ),
  );

  sl.registerFactory(
    () => DevicePairingBloc(repository: sl()),
  );
}
