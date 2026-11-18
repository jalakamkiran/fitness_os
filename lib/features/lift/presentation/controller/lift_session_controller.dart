import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:fitness_os/features/lift/data/lift_store.dart';
import 'package:fitness_os/features/lift/data/lift_sync_service.dart';
import 'package:fitness_os/features/lift/data/lift_watch_bridge.dart';
import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:fitness_os/features/lift/domain/session_runner.dart';
import 'package:fitness_os/features/lift/domain/strength_set.dart';

class LiftSessionController extends ChangeNotifier {
  LiftSessionController({
    required LiftStore store,
    required LiftWatchBridge bridge,
    required LiftSyncService sync,
    required HuaweiBtChannel channel,
    LiftCaptureMode captureMode = LiftCaptureMode.reply,
  })  : _store = store,
        _bridge = bridge,
        _sync = sync,
        _channel = channel,
        _captureMode = captureMode;

  final LiftStore _store;
  final LiftWatchBridge _bridge;
  final LiftSyncService _sync;
  final HuaweiBtChannel _channel;
  final LiftCaptureMode _captureMode;

  SessionRunner? _runner;
  StreamSubscription<LiftReplyEvent>? _sub;
  String? _lastReplyText;
  Timer? _debouncedSync;

  LiftRunnerState get state => _runner?.state ?? const LiftRunnerState(phase: LiftRunnerPhase.idle);

  PlannedSet? get currentSet => _runner?.currentSet;

  String? get lastReplyText => _lastReplyText;

  Future<void> ensureConfigured() => _bridge.configure(enabled: true);

  Future<void> startSession(PlannedSession session) async {
    await ensureConfigured();
    final sets = session.expand();
    _runner = SessionRunner(
      session: session,
      plannedSets: sets,
      captureMode: _captureMode,
    )..start();
    await _sub?.cancel();
    _sub = _bridge.events.listen(_onLiftEvent);
    await _channel.liftStartForeground(
      title: 'Fathom Lift',
      body: session.title,
    );
    await _notifyCurrentSet(session);
    notifyListeners();
  }

  Future<void> _notifyCurrentSet(PlannedSession session) async {
    final set = currentSet;
    if (set == null) return;
    final title = 'Set ${set.globalIndex}/${session.expand().length} · ${set.name}';
    final body = '${set.plannedKg} kg × ${set.plannedReps} · rest ${set.restSec}s';
    final sent = await _bridge.sendSetNotification(
      set: set,
      sessionId: session.sessionId,
      title: title,
      body: body,
    );
    final sentAt = sent['sentAtMs'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    _runner?.onNotified(sentAt);
    notifyListeners();
  }

  Future<void> _onLiftEvent(LiftReplyEvent event) async {
    if (_runner == null) return;
    if (event.kind == 'lift_reply') {
      final record = _runner!.onReply(
        key: event.key,
        text: event.text,
        rxAtMs: event.rxAtMs,
      );
      if (record != null) {
        _lastReplyText = event.text;
        await _store.upsertStrengthSet(record);
        _scheduleSync();
        if (_runner!.state.phase == LiftRunnerPhase.notifying) {
          final session = _runner!.session;
          await _notifyCurrentSet(session);
        }
        notifyListeners();
      }
    } else if (event.kind == 'lift_frame' && _captureMode == LiftCaptureMode.ackOnly) {
      final record = _runner!.onAckFrame(rxAtMs: event.rxAtMs);
      if (record != null) {
        await _store.upsertStrengthSet(record);
        _scheduleSync();
        notifyListeners();
      }
    }
  }

  void _scheduleSync() {
    _debouncedSync?.cancel();
    _debouncedSync = Timer(const Duration(seconds: 30), () {
      unawaited(_sync.syncPending());
    });
  }

  Future<void> endSession() async {
    _runner?.end();
    await _sub?.cancel();
    await _sync.syncPending();
    await _channel.liftStopForeground();
    notifyListeners();
  }

  void pause() {
    _runner?.pause();
    notifyListeners();
  }

  void skipSet() {
    _runner?.skipCurrent();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debouncedSync?.cancel();
    super.dispose();
  }
}