import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_service.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/data/swim_reasoner_service.dart';

/// Registers export service and composes Forget wipe/busy with vitals.
///
/// Call **after** [initVitalsDependencies] so wipe extras compose rather than
/// overwrite.
Future<void> initDiagnosticsDependencies(GetIt sl) async {
  if (sl.isRegistered<AppDataExportService>()) return;

  sl.registerLazySingleton<AppDataExportService>(
    () {
      final pairing = sl<DevicePairingRepository>();
      return AppDataExportService(
        prefs: sl<SharedPreferences>(),
        isSyncInFlight: () => sl<HuaweiLink>().syncInFlight,
        isVitalsSyncOrMergeInFlight: () =>
            sl<VitalsRepository>().isSyncOrMergeInFlight,
        isForgetInFlight: () => pairing is DevicePairingRepositoryImpl
            ? pairing.forgetInFlight
            : false,
        isQwenInstalled: () => sl<SwimReasonerService>().qwen3.isInstalled(),
      );
    },
  );

  final pairing = sl<DevicePairingRepository>();
  if (pairing is DevicePairingRepositoryImpl) {
    final vitals = sl<VitalsRepository>();
    final export = sl<AppDataExportService>();
    pairing.onForgetWipeExtras = () async {
      await vitals.clearLocal();
      await export.pruneExportCache();
    };
    pairing.isForgetBlocked =
        () => vitals.isSyncOrMergeInFlight || export.exportInFlight;
  }
}
