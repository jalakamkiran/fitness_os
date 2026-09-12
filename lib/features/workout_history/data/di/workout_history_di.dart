import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/storage/store_invalidation.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/workout_history/data/gemini_coach_client.dart';
import 'package:fitness_os/features/workout_history/data/qwen3_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/data/repositories/workout_history_repository_impl.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/data/strength_session_export_service.dart';
import 'package:fitness_os/features/workout_history/data/swim_reasoner_service.dart';
import 'package:fitness_os/features/workout_history/data/workout_leftover_store.dart';
import 'package:fitness_os/features/workout_history/data/workout_tcx_export_service.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_bloc.dart';

/// Registers workout stores, repository, reasoner, strength export, and TCX export.
///
/// Does **not** assign Forget wipe/prune — diagnostics_di composes that in U6.
Future<void> initWorkoutHistoryDependencies(GetIt sl) async {
  if (!sl.isRegistered<RunSessionStore>()) {
    sl.registerLazySingleton<RunSessionStore>(RunSessionStore.new);
  }
  if (!sl.isRegistered<WorkoutLeftoverStore>()) {
    sl.registerLazySingleton<WorkoutLeftoverStore>(WorkoutLeftoverStore.new);
  }

  sl.registerLazySingleton<WorkoutHistoryRepository>(
    () => WorkoutHistoryRepositoryImpl(
      link: sl(),
      prefs: sl<SharedPreferences>(),
      leftoverStore: sl<WorkoutLeftoverStore>(),
      onSyncSettled: () => sl<StoreInvalidation>().notify(),
      runSessionStore: sl<RunSessionStore>(),
    ),
  );

  if (!sl.isRegistered<StrengthSessionExportService>()) {
    sl.registerLazySingleton<StrengthSessionExportService>(
      () {
        final pairing = sl<DevicePairingRepository>();
        return StrengthSessionExportService(
          repository: sl<WorkoutHistoryRepository>(),
          leftoverStore: sl<WorkoutLeftoverStore>(),
          isForgetInFlight: () => pairing is DevicePairingRepositoryImpl
              ? pairing.forgetInFlight
              : false,
          isSyncOrMergeInFlight: () =>
              sl<WorkoutHistoryRepository>().isSyncOrMergeInFlight,
        );
      },
    );
  }

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

  if (!sl.isRegistered<WorkoutTcxExportService>()) {
    sl.registerLazySingleton<WorkoutTcxExportService>(
      () {
        final pairing = sl<DevicePairingRepository>();
        return WorkoutTcxExportService(
          isForgetInFlight: () => pairing is DevicePairingRepositoryImpl
              ? pairing.forgetInFlight
              : false,
        );
      },
    );
  }

  sl.registerFactory(
    () => WorkoutHistoryBloc(
      repository: sl(),
      invalidation: sl.isRegistered<StoreInvalidation>()
          ? sl<StoreInvalidation>()
          : null,
    ),
  );
}
