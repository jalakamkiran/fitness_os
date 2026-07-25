import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';

/// Binds [OneShotAutoSync] to app lifecycle + fully-connected link events.
class AutoSyncLifecycle extends StatefulWidget {
  const AutoSyncLifecycle({
    super.key,
    required this.autoSync,
    required this.link,
    required this.child,
  });

  final OneShotAutoSync autoSync;
  final HuaweiLink link;
  final Widget child;

  @override
  State<AutoSyncLifecycle> createState() => _AutoSyncLifecycleState();
}

class _AutoSyncLifecycleState extends State<AutoSyncLifecycle>
    with WidgetsBindingObserver {
  StreamSubscription<HuaweiLinkEvent>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _linkSub = widget.link.events.listen(_onLinkEvent);
    // Cold open: treat as resume (lifecycle observer does not re-emit current).
    widget.autoSync.onResumed();
  }

  void _onLinkEvent(HuaweiLinkEvent event) {
    if (event is LinkStateChanged &&
        isAutoSyncSessionReady(widget.link.state)) {
      widget.autoSync.onSessionReady();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.autoSync.handleLifecycle(state);
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
