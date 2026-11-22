import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fitness_os/app/background_dependencies.dart';
import 'package:fitness_os/core/backend/backend_config.dart';
import 'package:fitness_os/core/backend/backend_sync_service.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';
import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:get_it/get_it.dart';

const _kBackgroundWatchSync = true;

@pragma('vm:entry-point')
Future<void> backgroundSyncMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initBackgroundDependencies();

  const channel = MethodChannel('fathom/background_sync');
  var aborted = false;
  channel.setMethodCallHandler((call) async {
    if (call.method == 'abort') {
      aborted = true;
    }
    return null;
  });

  if (!BackendConfig.isEnabled) {
    await channel.invokeMethod('done', {
      'ok': true,
      'watchSynced': false,
      'pushed': 0,
    });
    return;
  }

  final sl = GetIt.I;
  final pusher = sl<BackendPusher>();
  var lastPushOk = false;

  if (!aborted) {
    await SentrySyncInstrumentation.addBackendSyncBreadcrumb('background_push');
    final push1 = await pusher.push(SyncTrigger.background);
    lastPushOk = push1.ok;
  }

  var watchSynced = false;
  if (_kBackgroundWatchSync && !aborted) {
    final pairing = sl<DevicePairingRepository>();
    final link = sl<HuaweiLink>();
  final workouts = sl<WorkoutHistoryRepository>();
    final vitals = sl<VitalsRepository>();
    try {
      await pairing.startLink();
      await SentrySyncInstrumentation.addBackendSyncBreadcrumb('watch_wait');
      await pairing.reconnectRemembered().timeout(const Duration(seconds: 90));
      if (isAutoSyncSessionReady(link.state) && !aborted) {
        await workouts.syncFromWatch().timeout(const Duration(minutes: 4));
        if (!aborted) {
          await vitals.syncFromWatch().timeout(const Duration(minutes: 4));
          watchSynced = true;
          await SentrySyncInstrumentation.addBackendSyncBreadcrumb(
            'watch_synced',
            data: const {'outcome': 'ok'},
          );
        }
      }
    } catch (_) {
      await SentrySyncInstrumentation.addBackendSyncBreadcrumb(
        'watch_synced',
        data: const {'outcome': 'error'},
      );
    }
  }

  if (!aborted) {
    final push2 = await pusher.push(SyncTrigger.background);
    lastPushOk = push2.ok;
    await SentrySyncInstrumentation.addBackendSyncBreadcrumb('background_push');
    final service = sl<BackendSyncService>();
    await service.reconcileIfDue();
  }

  if (!aborted) {
    try {
      await sl<HuaweiLink>().disconnect();
    } catch (_) {}
  }

  await channel.invokeMethod('done', {
    'ok': lastPushOk,
    'watchSynced': watchSynced,
    'pushed': lastPushOk ? 1 : 0,
  });
}