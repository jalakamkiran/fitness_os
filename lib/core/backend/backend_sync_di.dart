import 'package:dio/dio.dart';
import 'package:fitness_os/core/backend/backend_config.dart';
import 'package:fitness_os/core/backend/backend_sync_service.dart';
import 'package:fitness_os/core/backend/backend_sync_telemetry.dart';
import 'package:fitness_os/core/backend/backend_transport.dart';
import 'package:fitness_os/core/backend/local_sync_snapshot.dart';
import 'package:fitness_os/core/backend/sync_ledger_store.dart';
import 'package:fitness_os/core/backend/sync_record_validator.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
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

  final sl = GetIt.I;
  sl.registerLazySingleton<BackendSyncService>(
    () => BackendSyncService(
      transport: DioBackendTransport(dio),
      ledger: FileSyncLedgerStore(
        () async => await getApplicationSupportDirectory(),
        prefs: sl<SharedPreferences>(),
        telemetry: SentryBackendSyncTelemetry(),
      ),
      snapshot: LocalSyncSnapshot(
        workouts: sl<WorkoutHistoryRepository>(),
        vitals: sl<VitalsRepository>(),
      ),
      validator: SyncRecordValidator(),
      prefs: sl<SharedPreferences>(),
    ),
  );
  sl.registerLazySingleton<BackendPusher>(() => sl<BackendSyncService>());
}