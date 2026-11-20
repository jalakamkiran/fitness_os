import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/backend/backend_config.dart';
import 'package:fitness_os/core/backend/backend_sync_di.dart';
import 'package:fitness_os/core/observability/sentry_config.dart';
import 'package:fitness_os/core/observability/sentry_privacy_scrub.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync_di.dart';
import 'package:fitness_os/features/device_pairing/data/di/device_pairing_di.dart';
import 'package:fitness_os/features/vitals/data/di/vitals_di.dart';
import 'package:fitness_os/features/workout_history/data/di/workout_history_di.dart';

final _sl = GetIt.instance;

/// Minimal DI for headless background sync (no UI, Gemma, notifications).
Future<void> initBackgroundDependencies() async {
  if (SentryConfig.shouldInitialize) {
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = SentryConfig.dsn.trim();
          options.sendDefaultPii = false;
          options.tracesSampleRate = 0.0;
          options.beforeSend = SentryPrivacyScrub.beforeSend;
          options.beforeBreadcrumb = SentryPrivacyScrub.beforeBreadcrumb;
        },
      );
    } catch (e, st) {
      debugPrint('Sentry background init failed: $e\n$st');
    }
  }

  if (!_sl.isRegistered<SharedPreferences>()) {
    _sl.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  }

  await initDevicePairingDependencies(_sl);
  await initWorkoutHistoryDependencies(_sl);
  await initVitalsDependencies(_sl);
  registerOneShotAutoSync(_sl);
  await initBackendSync();

  if (!BackendConfig.isEnabled) return;
}