import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Thin wrapper around Sentry for backend sync (injectable in tests).
abstract class BackendSyncTelemetry {
  Future<void> breadcrumb(String stage, {Map<String, Object?> data = const {}});

  Future<void> ledgerReset(String reason);
}

class SentryBackendSyncTelemetry implements BackendSyncTelemetry {
  @override
  Future<void> breadcrumb(
    String stage, {
    Map<String, Object?> data = const {},
  }) =>
      SentrySyncInstrumentation.addBackendSyncBreadcrumb(stage, data: data);

  @override
  Future<void> ledgerReset(String reason) async {
    await breadcrumb('reconcile', data: {'reason': reason});
    if (!Sentry.isEnabled) return;
    await Sentry.captureMessage(
      'backend_sync_ledger_reset',
      level: SentryLevel.warning,
    );
  }
}

class NoOpBackendSyncTelemetry implements BackendSyncTelemetry {
  @override
  Future<void> breadcrumb(String stage,
          {Map<String, Object?> data = const {}}) async =>
      {};

  @override
  Future<void> ledgerReset(String reason) async => {};
}