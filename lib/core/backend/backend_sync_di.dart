import 'package:dio/dio.dart';
import 'package:fitness_os/core/backend/backend_config.dart';
import 'package:fitness_os/core/backend/backend_sync_service.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> initBackendSync() async {
  if (!BackendConfig.isEnabled) {
    return;
  }

  final dio = Dio(BaseOptions(
    baseUrl: '${BackendConfig.baseUrl}/api/v1',
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
  ));

  GetIt.I.registerLazySingleton<BackendSyncService>(
    () => BackendSyncService(
      dio: dio,
      prefs: GetIt.I<SharedPreferences>(),
      workoutRepo: GetIt.I<WorkoutHistoryRepository>(),
      vitalsRepo: GetIt.I<VitalsRepository>(),
    ),
  );
}
