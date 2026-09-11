import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/features/workout_history/data/gemini_coach_client.dart';
import 'package:fitness_os/features/workout_history/data/qwen3_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/data/repositories/workout_history_repository_impl.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/data/swim_reasoner_service.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_bloc.dart';

Future<void> initWorkoutHistoryDependencies(GetIt sl) async {
  if (!sl.isRegistered<RunSessionStore>()) {
    sl.registerLazySingleton<RunSessionStore>(RunSessionStore.new);
  }

  sl.registerLazySingleton<WorkoutHistoryRepository>(
    () => WorkoutHistoryRepositoryImpl(
      link: sl(),
      prefs: sl<SharedPreferences>(),
      onSyncSettled: () => sl<StoreInvalidation>().notify(),
      runSessionStore: sl<RunSessionStore>(),
    ),
  );

  if (!sl.isRegistered<GeminiCoachClient>()) {
    sl.registerLazySingleton<GeminiCoachClient>(
      () => GeminiCoachClient(prefs: sl<SharedPreferences>()),
    );
  }

  if (!sl.isRegistered<Qwen3SwimReasoner>()) {
    sl.registerLazySingleton<Qwen3SwimReasoner>(Qwen3SwimReasoner.new);
  }

  if (!sl.isRegistered<SwimReasonerService>()) {
    sl.registerLazySingleton<SwimReasonerService>(
      () => SwimReasonerService(qwen3: sl()),
    );
  }

  sl.registerFactory(
    () => WorkoutHistoryBloc(repository: sl()),
  );
}
