import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'package:fitness_os/core/huawei/huawei_link.dart' show LinkState;
import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';

/// Auto-sync requires full pairing ([LinkState.connected]) only.
///
/// [HuaweiLink.sessionReady] is also true for [LinkState.gateAIncomplete],
/// but that state must not arm/consume the one-shot (sync would no-op).
bool isAutoSyncSessionReady(LinkState state) => state == LinkState.connected;

/// Outcome of a single auto-sync schedule attempt (R10).
enum AutoSyncOutcome {
  /// Workouts + vitals pass started (and completed when awaited).
  ran,

  /// App not in foreground — ignored.
  inactive,

  /// Encrypted session not ready yet — not consumed; may retry later.
  notReady,

  /// Already started a pass for this resume cycle.
  alreadyFired,

  /// Manual/native Sync owns the shared single-flight lock.
  rejectedBusy,
}

/// Optional hook reserved so tests can prove sticky FGS is never started (R11).
typedef ForegroundServiceStarter = Future<void> Function();

/// One-shot auto-sync on open / resume / session-ready.
///
/// Shares the Huawei Sync single-flight lock with manual Sync via
/// [isSyncBusy] / repository calls into `HuaweiLink`. Never starts a
/// sticky foreground service.
class OneShotAutoSync {
  OneShotAutoSync({
    required bool Function() isSessionReady,
    required bool Function() isSyncBusy,
    required Future<void> Function() runPass,
    ForegroundServiceStarter? startForegroundService,
  })  : _isSessionReady = isSessionReady,
        _isSyncBusy = isSyncBusy,
        _runPass = runPass,
        _startForegroundService = startForegroundService;

  final bool Function() _isSessionReady;
  final bool Function() _isSyncBusy;
  final Future<void> Function() _runPass;

  /// Injected only for tests; production wiring leaves this null and never calls it.
  final ForegroundServiceStarter? _startForegroundService;

  bool _inForeground = false;
  int _resumeGeneration = 0;
  int? _consumedGeneration;
  bool _passInFlight = false;
  int _passStarts = 0;

  /// How many auto-sync passes actually started (test seam).
  int get passStarts => _passStarts;

  /// Count of sticky FGS starts — remains 0 because starter is never invoked (R11).
  int get foregroundServiceStarts => 0;

  bool get passInFlight => _passInFlight;

  /// Whether a starter was injected (tests); production leaves this false.
  bool get hasForegroundServiceStarter => _startForegroundService != null;

  /// Cold open / return to foreground — arms a new one-shot window.
  ///
  /// Idempotent while already foregrounded so cold-open arming plus a
  /// subsequent [AppLifecycleState.resumed] does not burn two generations.
  void onResumed() {
    if (_inForeground) {
      unawaited(trySchedule());
      return;
    }
    _resumeGeneration++;
    _inForeground = true;
    unawaited(trySchedule());
  }

  /// Session became ready while foregrounded.
  void onSessionReady() {
    if (!_inForeground) return;
    unawaited(trySchedule());
  }

  void onBackgrounded() {
    _inForeground = false;
  }

  void handleLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onResumed();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        onBackgrounded();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Schedule at most one pass for the current resume generation.
  Future<AutoSyncOutcome> trySchedule() async {
    if (!_inForeground) {
      return _finishSchedule(AutoSyncOutcome.inactive);
    }
    if (_consumedGeneration == _resumeGeneration) {
      return _finishSchedule(AutoSyncOutcome.alreadyFired);
    }
    if (!_isSessionReady()) {
      return _finishSchedule(AutoSyncOutcome.notReady);
    }
    if (_passInFlight || _isSyncBusy()) {
      // Do not consume — a later session-ready in this resume may retry.
      return _finishSchedule(AutoSyncOutcome.rejectedBusy);
    }

    // Claim synchronously before any await (single-flight vs concurrent schedule).
    _consumedGeneration = _resumeGeneration;
    _passInFlight = true;
    _passStarts++;
    try {
      // R11: never start sticky FGS — [_startForegroundService] is never invoked.
      await _runPass();
      return _finishSchedule(AutoSyncOutcome.ran);
    } finally {
      _passInFlight = false;
    }
  }

  Future<AutoSyncOutcome> _finishSchedule(AutoSyncOutcome outcome) async {
    await SentrySyncInstrumentation.addScheduleBreadcrumb(outcome);
    return outcome;
  }
}
