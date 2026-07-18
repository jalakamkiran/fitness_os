import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/vitals/data/repositories/vitals_repository_impl.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';

Future<void> initVitalsDependencies(GetIt sl) async {
  if (!sl.isRegistered<StoreInvalidation>()) {
    sl.registerSingleton<StoreInvalidation>(StoreInvalidation());
  }

  sl.registerLazySingleton<VitalsRepository>(
    () => VitalsRepositoryImpl(
      link: sl(),
      prefs: sl<SharedPreferences>(),
    ),
  );

  final pairing = sl<DevicePairingRepository>();
  if (pairing is DevicePairingRepositoryImpl) {
    pairing.onForgetWipeExtras = () => sl<VitalsRepository>().clearLocal();
    pairing.onForgot = () => sl<StoreInvalidation>().notify();
    pairing.isForgetBlocked =
        () => sl<VitalsRepository>().isSyncOrMergeInFlight;
  }

  sl.registerFactory(
    () => VitalsBloc(
      repository: sl(),
      invalidation: sl<StoreInvalidation>(),
    ),
  );
}
