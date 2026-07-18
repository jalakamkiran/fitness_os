import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/workout_history/data/repositories/workout_history_repository_impl.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_bloc.dart';

Future<void> initWorkoutHistoryDependencies(GetIt sl) async {
  sl.registerLazySingleton<WorkoutHistoryRepository>(
    () => WorkoutHistoryRepositoryImpl(
      link: sl(),
      prefs: sl<SharedPreferences>(),
    ),
  );

  sl.registerFactory(
    () => WorkoutHistoryBloc(repository: sl()),
  );
}
