import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';

/// Allowlisted Performance helpers for Huawei sync (no MethodChannel payloads).
abstract final class SentrySyncInstrumentation {
  static const opSync = 'sync';
  static const namePass = 'autosync.pass';
  static const nameWorkouts = 'sync.workouts';
  static const nameVitals = 'sync.vitals';
  static const nameConnect = 'link.connect';

  /// Soft / schedule outcomes must never become Issues — spans/breadcrumbs only.
  static Future<void> addScheduleBreadcrumb(AutoSyncOutcome outcome) async {
    if (!Sentry.isEnabled) return;
    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'autosync.schedule',
        message: outcome.name,
        level: SentryLevel.info,
        data: {'outcome': outcome.name},
      ),
    );
  }

  static Future<void> addLinkStateBreadcrumb(String stateName) async {
    if (!Sentry.isEnabled) return;
    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'link.state',
        message: stateName,
        level: SentryLevel.info,
        data: {'state': stateName},
      ),
    );
  }

  static Future<void> addAbandonedBreadcrumb({
    required String channel,
    required int elapsedMs,
  }) async {
    if (!Sentry.isEnabled) return;
    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'sync.abandoned',
        message: channel,
        level: SentryLevel.warning,
        data: {
          'channel': channel,
          'elapsed_ms': elapsedMs,
        },
      ),
    );
  }

  static ISentrySpan? startPassTransaction({
    required String trigger,
    String? windowClass,
  }) {
    if (!Sentry.isEnabled) return null;
    final txn = Sentry.startTransaction(
      namePass,
      opSync,
      bindToScope: true,
    );
    txn.setTag('trigger', trigger);
    if (windowClass != null) txn.setTag('window', windowClass);
    return txn;
  }

  static ISentrySpan? startChild(ISentrySpan? parent, String name) {
    if (!Sentry.isEnabled) return null;
    if (parent != null && !parent.finished) {
      return parent.startChild(name, description: name);
    }
    // Orphan span when no pass transaction is bound (defensive).
    return Sentry.startTransaction(name, opSync, bindToScope: false);
  }

  static Future<void> finishWithStatus(
    ISentrySpan? span, {
    required String status,
    bool? partial,
    int? count,
  }) async {
    if (span == null) return;
    span.setTag('status', status);
    if (partial != null) span.setTag('partial', partial.toString());
    if (count != null) span.setData('count', count);
    final sentryStatus = _mapStatus(status);
    await span.finish(status: sentryStatus);
  }

  static SpanStatus _mapStatus(String status) {
    switch (status) {
      case 'ok':
      case 'empty':
        return const SpanStatus.ok();
      case 'busy':
      case 'notReady':
      case 'not_ready':
        return const SpanStatus.unavailable();
      case 'stuck':
      case 'partial':
      case 'partial_batch':
      case 'partialBatch':
        return const SpanStatus.deadlineExceeded();
      case 'abandoned':
        return const SpanStatus.deadlineExceeded();
      case 'error':
        return const SpanStatus.internalError();
      default:
        return const SpanStatus.unknownError();
    }
  }

  /// Test seam for [_mapStatus].
  static SpanStatus mapStatusForTest(String status) => _mapStatus(status);

  /// Dual budget: long windows (full history) get a larger MethodChannel cap.
  static Duration timeoutForWindow({
    required int startUnix,
    required int endUnix,
  }) {
    final spanSec = endUnix - startUnix;
    // ~60 days or more → treat as full-history enrichment risk.
    if (spanSec >= 60 * 24 * 60 * 60) {
      return const Duration(minutes: 20);
    }
    return const Duration(minutes: 4);
  }

  static String windowClass({
    required int startUnix,
    required int endUnix,
  }) {
    final spanSec = endUnix - startUnix;
    if (spanSec >= 60 * 24 * 60 * 60) return 'full_history';
    return 'incremental';
  }

  static const _allowedBackendSyncDataKeys = {
    'trigger',
    'outcome',
    'pendingCount',
    'attempted',
    'accepted',
    'rejected',
    'chunkIndex',
    'chunkCount',
    'httpStatus',
    'durationMs',
    'reason',
    'kind',
  };

  static Future<void> addBackendSyncBreadcrumb(
    String stage, {
    Map<String, Object?> data = const {},
  }) async {
    if (!Sentry.isEnabled) return;
    final filtered = <String, Object?>{};
    for (final e in data.entries) {
      if (_allowedBackendSyncDataKeys.contains(e.key)) {
        filtered[e.key] = e.value;
      }
    }
    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'backend.sync',
        message: stage,
        level: SentryLevel.info,
        data: filtered,
      ),
    );
  }

  /// MethodChannel sync watchdog — abandoned is span/breadcrumb only (no Issue).
  static Future<T> invokeWithTimeout<T>({
    required Future<T> future,
    required Duration timeout,
    required String channel,
    required T Function() onAbandoned,
  }) async {
    final sw = Stopwatch()..start();
    try {
      return await future.timeout(timeout);
    } on TimeoutException {
      await addAbandonedBreadcrumb(
        channel: channel,
        elapsedMs: sw.elapsedMilliseconds,
      );
      return onAbandoned();
    }
  }
}
