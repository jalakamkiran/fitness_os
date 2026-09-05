import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:get_it/get_it.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:fitness_os/core/observability/sentry_config.dart';
import 'package:fitness_os/core/observability/sentry_privacy_scrub.dart';
import 'package:fitness_os/features/food/data/food_notification_scheduler.dart';
import 'package:fitness_os/features/food/domain/food_capture_intent.dart';
import 'package:fitness_os/app/app.dart';
import 'package:fitness_os/app/routing/route_registry.dart';
import 'package:fitness_os/core/di/injector.dart';

/// App entry used by [main] — Sentry wraps this when enabled.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SentryConfig.shouldInitialize) {
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = SentryConfig.dsn.trim();
          options.sendDefaultPii = false;
          options.anrEnabled = true;
          options.enableNdkScopeSync = true;
          options.tracesSampleRate = 1.0;
          options.beforeSend = SentryPrivacyScrub.beforeSend;
          options.beforeSendTransaction =
              SentryPrivacyScrub.beforeSendTransaction;
          options.beforeBreadcrumb = SentryPrivacyScrub.beforeBreadcrumb;
          options.environment = kReleaseMode
              ? 'release'
              : (kProfileMode ? 'profile' : 'debug');
        },
        appRunner: _runAppBody,
      );
      return;
    } catch (e, st) {
      debugPrint('Sentry init failed — continuing without observability: $e\n$st');
    }
  }

  await _runAppBody();
}

Future<void> _runAppBody() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezones for notifications
  tz.initializeTimeZones();
  try {
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone));
  } catch (e) {
    debugPrint('Failed to set local timezone: $e');
    // Fallback to UTC
    tz.setLocalLocation(tz.getLocation('UTC'));
  }

  await FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
  );

  await initDependencies();
  
  // Initialize notification plugin after DI
  final scheduler = GetIt.I<FoodNotificationScheduler>();
  await scheduler.initialize(
    onNotificationTap: _onNotificationResponse,
  );

  // Check for cold-start notification
  final plugin = FlutterLocalNotificationsPlugin();
  final launchDetails = await plugin.getNotificationAppLaunchDetails();
  if (launchDetails?.didNotificationLaunchApp == true) {
    final payload = launchDetails?.notificationResponse?.payload;
    if (payload != null && payload.isNotEmpty) {
      _handleNotificationPayload(payload);
    }
  }

  RouteRegistry.registerAll();
  runApp(const FitnessOsApp());
}

void _onNotificationResponse(NotificationResponse response) {
  final payload = response.payload;
  if (payload != null && payload.isNotEmpty) {
    _handleNotificationPayload(payload);
  }
}

void _handleNotificationPayload(String payload) {
  try {
    final parts = payload.split('|');
    if (parts.length == 2) {
      final slot = parts[0];
      final localDay = parts[1];
      
      // Validate slot
      const validSlots = {'breakfast', 'lunch', 'dinner', 'snack1', 'snack2'};
      if (!validSlots.contains(slot)) return;
      
      // Validate day format
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(localDay)) return;
      
      FoodCaptureIntent.setPending(FoodCaptureIntent(
        slot: slot,
        localDay: localDay,
      ));
    }
  } catch (e) {
    debugPrint('Failed to parse notification payload: $e');
  }
}
