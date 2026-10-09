import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';

/// Registers [ProgramStore] (+ optional [ProgramsController]) as singletons.
///
/// Does NOT set onForgetWipeExtras — diagnostics_di composes the wipe body.
void initProgramsDependencies(GetIt sl) {
  if (!sl.isRegistered<ProgramStore>()) {
    sl.registerLazySingleton<ProgramStore>(
      () => ProgramStore(prefs: sl<SharedPreferences>()),
    );
  }

  if (!sl.isRegistered<ProgramsController>()) {
    sl.registerLazySingleton<ProgramsController>(
      () => ProgramsController.fromGetIt(sl),
    );
  }
}
