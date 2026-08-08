import 'dart:async';

import 'package:flutter/widgets.dart';

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
  });

  final OneShotAutoSync autoSync;
  final HuaweiLink link;
  final DevicePairingRepository pairing;
  final Widget child;

  @override
  State<AutoSyncLifecycle> createState() => _AutoSyncLifecycleState();
}

class _AutoSyncLifecycleState extends State<AutoSyncLifecycle>
    with WidgetsBindingObserver {
  StreamSubscription<HuaweiLinkEvent>? _linkSub;
  bool _ensureInFlight = false;
  bool _ensureQueued = false;

  @override
  void initState() {
    super.initState();
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
      await widget.pairing.startLink();
      if (!widget.link.sessionReady) {
        final remembered = await widget.pairing.loadRemembered();
        if (remembered != null) {
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
        unawaited(_ensureSessionThenArm());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
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
