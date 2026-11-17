import 'package:get_it/get_it.dart';

import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:fitness_os/features/lift/data/lift_store.dart';
import 'package:fitness_os/features/lift/data/lift_sync_service.dart';
import 'package:fitness_os/features/lift/data/lift_watch_bridge.dart';
import 'package:fitness_os/features/lift/presentation/controller/lift_session_controller.dart';

void initLiftDependencies(GetIt sl) {
  if (!sl.isRegistered<LiftStore>()) {
    sl.registerLazySingleton<LiftStore>(() => LiftStore());
  }
  if (!sl.isRegistered<LiftWatchBridge>()) {
    sl.registerLazySingleton<LiftWatchBridge>(
      () => LiftWatchBridge(sl<HuaweiBtChannel>()),
    );
  }
  if (!sl.isRegistered<LiftSyncService>()) {
    sl.registerLazySingleton<LiftSyncService>(
      () => LiftSyncService(store: sl<LiftStore>()),
    );
  }
  if (!sl.isRegistered<LiftSessionController>()) {
    sl.registerFactory<LiftSessionController>(
      () => LiftSessionController(
        store: sl<LiftStore>(),
        bridge: sl<LiftWatchBridge>(),
        sync: sl<LiftSyncService>(),
      ),
    );
  }
}