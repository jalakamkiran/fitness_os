import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';
import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/features/home/data/repositories/home_repository_impl.dart';
import 'package:fitness_os/features/home/domain/repositories/home_repository.dart';
import 'package:fitness_os/features/home/domain/usecases/get_home_data.dart';
import 'package:fitness_os/features/home/presentation/bloc/home_bloc.dart';

void initHomeDependencies(GetIt sl) {
  sl.registerLazySingleton<HomeRepository>(
    () => HomeRepositoryImpl(
      prefs: sl<SharedPreferences>(),
      link: sl(),
      workouts: sl(),
      vitals: sl(),
      autoSync: sl.isRegistered<OneShotAutoSync>() ? sl() : null,
    ),
  );

  sl.registerLazySingleton(
    () => GetHomeData(repository: sl()),
  );

  sl.registerFactory(
    () => HomeBloc(
      getHomeData: sl(),
      repository: sl(),
      pairing: sl(),
      invalidation:
          sl.isRegistered<StoreInvalidation>() ? sl<StoreInvalidation>() : null,
    ),
  );
}
