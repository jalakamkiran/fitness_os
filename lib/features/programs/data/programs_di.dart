import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/programs/data/program_store.dart';

/// Registers [ProgramStore] as a singleton.
///
/// Does NOT set onForgetWipeExtras — diagnostics_di composes the wipe body.
void initProgramsDependencies(GetIt sl) {
  if (sl.isRegistered<ProgramStore>()) return;

  sl.registerLazySingleton<ProgramStore>(
    () => ProgramStore(prefs: sl<SharedPreferences>()),
  );
}
