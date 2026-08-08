import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fitness_os/core/observability/sentry_config.dart';
import 'package:fitness_os/core/observability/sentry_privacy_scrub.dart';

import 'app.dart';
import 'routing/route_registry.dart';
import '../core/di/injector.dart';

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

  await FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
  );

  await initDependencies();
  RouteRegistry.registerAll();
  runApp(const FitnessOsApp());
}
