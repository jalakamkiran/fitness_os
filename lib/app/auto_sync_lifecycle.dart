import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'package:fitness_os/core/backend/backend_sync_service.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitness_os/core/huawei/fos_huawei_log.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';

/// Binds [OneShotAutoSync] to app lifecycle + fully-connected link events.
///
/// Cold open / resume also starts the BT event subscription and reconnects a
/// remembered GT5 so encrypted-session Sync can arm without visiting Pairing.
class AutoSyncLifecycle extends StatefulWidget {
  const AutoSyncLifecycle({
    super.key,
    required this.autoSync,
    required this.link,
    required this.pairing,
    required this.child,
    this.backendPusher,
  });

  final OneShotAutoSync autoSync;
  final HuaweiLink link;
  final DevicePairingRepository pairing;
  final Widget child;
  final BackendPusher? backendPusher;

  @override
  State<AutoSyncLifecycle> createState() => _AutoSyncLifecycleState();
}

class _AutoSyncLifecycleState extends State<AutoSyncLifecycle>
    with WidgetsBindingObserver {
  StreamSubscription<HuaweiLinkEvent>? _linkSub;
  bool _ensureInFlight = false;
  bool _ensureQueued = false;
  BackendPusher? _pusher;

  @override
  void initState() {
    super.initState();
    _pusher = widget.backendPusher ??
        (GetIt.I.isRegistered<BackendPusher>() ? GetIt.I<BackendPusher>() : null);
    WidgetsBinding.instance.addObserver(this);
    _linkSub = widget.link.events.listen(_onLinkEvent);
    // Cold open: treat as resume (lifecycle observer does not re-emit current).
    unawaited(_ensureSessionThenArm());
  }

  void _onLinkEvent(HuaweiLinkEvent event) {
    if (event is LinkStateChanged &&
        isAutoSyncSessionReady(widget.link.state)) {
      widget.autoSync.onSessionReady();
    }
  }

  Future<void> _ensureSessionThenArm() async {
    if (_ensureInFlight) {
      _ensureQueued = true;
      return;
    }
    _ensureInFlight = true;
    try {
      if (GetIt.I.isRegistered<SharedPreferences>()) {
        try {
          await GetIt.I<SharedPreferences>().reload();
        } catch (_) {}
      }
      unawaited(_pusher?.push(SyncTrigger.open));
      unawaited(
        SentrySyncInstrumentation.addBackendSyncBreadcrumb('open_push'),
      );

      await widget.pairing.startLink();
      if (!widget.link.sessionReady) {
        final remembered = await widget.pairing.loadRemembered();
        if (remembered != null) {
          unawaited(
            SentrySyncInstrumentation.addBackendSyncBreadcrumb(
              'watch_wait',
              data: const {'outcome': 'disconnected'},
            ),
          );
          FosHuaweiLog.i(
            'lifecycle reconnect remembered=${remembered.name}',
            op: 'reconnect',
          );
          final result = await widget.pairing.reconnectRemembered();
          result.fold(
            (f) => FosHuaweiLog.w(
              'lifecycle reconnect failed: ${f.message}',
              op: 'reconnect',
            ),
            (_) => FosHuaweiLog.i(
              'lifecycle reconnect ok state=${widget.link.state}',
              op: 'reconnect',
            ),
          );
        }
      }
    } catch (e) {
      FosHuaweiLog.e('lifecycle ensureSession failed', error: e, op: 'reconnect');
    } finally {
      _ensureInFlight = false;
    }
    widget.autoSync.onResumed();

    if (_ensureQueued) {
      _ensureQueued = false;
      unawaited(_ensureSessionThenArm());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _pusher?.startRetryTimer();
        unawaited(_ensureSessionThenArm());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _pusher?.stopRetryTimer();
        widget.autoSync.onBackgrounded();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_linkSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
