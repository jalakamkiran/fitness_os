import 'dart:async';
import 'dart:convert';

import 'package:fitness_os/core/huawei/fos_huawei_log.dart';
import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Sole Flutter caller of the Huawei platform channel (Phase 1 pairing-scoped).
class HuaweiLink {
  HuaweiLink({HuaweiBtChannel? channel})
      : _channel = channel ?? HuaweiBtChannel();

  final HuaweiBtChannel _channel;
  StreamSubscription<HuaweiBtEvent>? _sub;
  final _controller = StreamController<HuaweiLinkEvent>.broadcast();

  LinkState _state = LinkState.disconnected;
  String? _lastError;
  String? _recoveryHint;
  final List<DiscoveredDevice> _discovered = [];
  bool _pairInFlight = false;
  bool _syncInFlight = false;

  LinkState get state => _state;
  String? get lastError => _lastError;
  String? get recoveryHint => _recoveryHint;
  List<DiscoveredDevice> get discovered => List.unmodifiable(_discovered);
  Stream<HuaweiLinkEvent> get events => _controller.stream;
  bool get pairInFlight => _pairInFlight;
  /// Flutter mirror of native Sync single-flight (native remains SoT).
  bool get syncInFlight => _syncInFlight;

  /// Encrypted-session radio bar Sync already uses (never BT-up alone).
  bool get sessionReady =>
      state == LinkState.connected || state == LinkState.gateAIncomplete;

  /// Default activity Sync window: last 14 local days.
  static const activityWindowDays = 14;

  Future<void> start() async {
    FosHuaweiLog.i('link.start — subscribe to BT events', op: 'link');
    await _sub?.cancel();
    _sub = _channel.events().listen(_onBtEvent);
  }

  Future<void> dispose() async {
    FosHuaweiLog.i('link.dispose', op: 'link');
    await _sub?.cancel();
    await _controller.close();
  }

  Future<bool> ensurePermissions() async {
    final ok = await _channel.checkPermissions();
    FosHuaweiLog.d('checkPermissions=$ok', op: 'perms');
    if (ok) return true;
    final granted = await _channel.requestPermissions();
    FosHuaweiLog.i('requestPermissions=$granted', op: 'perms');
    if (!granted) {
      _setState(LinkState.permissionRequired);
    }
    return granted;
  }

  Future<void> startScan() async {
    FosHuaweiLog.i('startScan requested (state=$_state)', op: 'scan');
    final permitted = await ensurePermissions();
    if (!permitted) {
      FosHuaweiLog.w('startScan aborted — permissions denied', op: 'scan');
      return;
    }

    final adapter = await _channel.getAdapterState();
    FosHuaweiLog.d('adapterState=$adapter', op: 'scan');
    if (adapter != 'on') {
      _lastError = 'Bluetooth adapter is off';
      _setState(LinkState.disconnected);
      return;
    }

    _discovered.clear();
    _setState(LinkState.scanning);
    try {
      await _channel.startBleDiscovery();
      FosHuaweiLog.i('native startBleDiscovery invoked', op: 'scan');
    } on PlatformException catch (e) {
      FosHuaweiLog.e('startBleDiscovery failed', error: e, op: 'scan');
      _mapPlatformError(e);
    }
  }

  Future<void> stopScan() async {
    FosHuaweiLog.i('stopScan requested (state=$_state)', op: 'scan');
    try {
      await _channel.stopBleDiscovery();
    } on PlatformException catch (e) {
      FosHuaweiLog.e('stopBleDiscovery failed', error: e, op: 'scan');
    }
    // Always leave scanning UI even if native said "wasn't scanning".
    if (_state == LinkState.scanning) {
      _discovered.clear();
      _setState(LinkState.disconnected);
    }
  }

  Future<void> connectAndAuthenticate(String mac) async {
    if (_pairInFlight) {
      FosHuaweiLog.w(
        'connectAndAuthenticate ignored — pair already in flight',
        op: 'pair',
      );
      return;
    }
    _pairInFlight = true;
    FosHuaweiLog.i('connectAndAuthenticate mac=${_redact(mac)}', op: 'pair');
    try {
      final permitted = await ensurePermissions();
      if (!permitted) return;

      // Stop scan without emitting native "disconnected" (avoids UI flicker).
      await _channel.stopBleDiscovery(emitDisconnected: false);
      _setState(LinkState.connecting);
      final connected = _waitForConnectionState('connected');
      await _channel.connect(mac: mac);
      final ok = await connected.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      if (!ok) {
        FosHuaweiLog.w('RFCOMM connect timed out', op: 'pair');
        _lastError = 'RFCOMM connect timed out';
        _setState(LinkState.reconnectFailed);
        return;
      }

      _setState(LinkState.authenticating);
      final outcome = await _channel.authenticate();
      FosHuaweiLog.i('authenticate outcome=$outcome', op: 'auth');
      if (outcome == 'Ready') {
        _setState(LinkState.gateAIncomplete);
      } else {
        _setState(LinkState.authFailed);
      }
    } on PlatformException catch (e) {
      FosHuaweiLog.e('connectAndAuthenticate failed', error: e, op: 'pair');
      _mapPlatformError(e);
    } finally {
      _pairInFlight = false;
    }
  }

  /// Cold-start reconnect for a remembered MAC (no scan).
  Future<void> reconnect(String mac) async {
    if (_pairInFlight) {
      FosHuaweiLog.w('reconnect ignored — pair already in flight', op: 'reconnect');
      return;
    }
    _pairInFlight = true;
    FosHuaweiLog.i('reconnect mac=${_redact(mac)}', op: 'reconnect');
    try {
      final permitted = await ensurePermissions();
      if (!permitted) return;

      final adapter = await _channel.getAdapterState();
      if (adapter != 'on') {
        _lastError = 'Bluetooth adapter is off — waiting';
        _setState(LinkState.disconnected);
        return;
      }

      final hasSecrets = await _channel.hasSecrets();
      FosHuaweiLog.d('hasSecrets=$hasSecrets', op: 'reconnect');
      if (!hasSecrets) {
        _lastError = 'Remembered device is missing secrets — re-pair required';
        _recoveryHint = 'r11_repair';
        _setState(LinkState.authFailed);
        return;
      }

      _setState(LinkState.connecting);
      final connected = _waitForConnectionState('connected');
      await _channel.connect(mac: mac);
      final ok = await connected.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      if (!ok) {
        _lastError = 'Reconnect RFCOMM timed out';
        _setState(LinkState.reconnectFailed);
        return;
      }
      _setState(LinkState.authenticating);
      final outcome = await _channel.authenticate();
      FosHuaweiLog.i('reconnect auth outcome=$outcome', op: 'reconnect');
      if (outcome == 'Ready') {
        _setState(LinkState.gateAIncomplete);
      } else {
        _lastError = 'Reconnect authentication failed';
        _setState(LinkState.reconnectFailed);
      }
    } on PlatformException catch (e) {
      _lastError = e.message;
      FosHuaweiLog.e('reconnect failed', error: e, op: 'reconnect');
      if (e.code == 'illegal_state' &&
          (e.message ?? '').toLowerCase().contains('bond')) {
        _setState(LinkState.bondRequired);
      } else {
        _setState(LinkState.reconnectFailed);
      }
    } finally {
      _pairInFlight = false;
    }
  }

  Future<bool> _waitForConnectionState(String desired) {
    final completer = Completer<bool>();
    late StreamSubscription<HuaweiBtEvent> sub;
    sub = _channel.events().listen((event) {
      if (event is ConnectionStateEvent && event.state == desired) {
        if (!completer.isCompleted) completer.complete(true);
        sub.cancel();
      } else if (event is ErrorEvent && event.code == 'connect_failed') {
        if (!completer.isCompleted) completer.complete(false);
        sub.cancel();
      }
    });
    return completer.future;
  }

  Future<void> setAuthKey(String userId) {
    FosHuaweiLog.i(
      'setAuthKey len=${userId.trim().length} (value redacted)',
      op: 'auth',
    );
    return _channel.setAuthKey(userId);
  }

  Future<bool> hasSecrets() => _channel.hasSecrets();

  Future<void> clearSecrets() {
    FosHuaweiLog.i('clearSecrets', op: 'secrets');
    return _channel.clearSecrets();
  }

  Future<void> disconnect() async {
    FosHuaweiLog.i('disconnect (state=$_state)', op: 'link');
    await _channel.disconnect();
    _setState(LinkState.disconnected);
  }

  /// Gate B radio call. Requires authenticated session (`connected` or
  /// `gateAIncomplete`). Product unlock is enforced by workout_history.
  Future<WorkoutSyncResult> syncWorkouts({
    required int startUnix,
    required int endUnix,
  }) async {
    if (_syncInFlight) {
      return const WorkoutSyncResult(
        status: WorkoutSyncStatus.busy,
        message: 'Another Sync is already in progress',
        workouts: [],
      );
    }
    if (state != LinkState.connected &&
        state != LinkState.gateAIncomplete) {
      FosHuaweiLog.w(
        'syncWorkouts rejected — linkState=$state',
        op: 'sync',
      );
      return const WorkoutSyncResult(
        status: WorkoutSyncStatus.notReady,
        message: 'Connect and authenticate first',
        workouts: [],
      );
    }
    _syncInFlight = true;
    final window = SentrySyncInstrumentation.windowClass(
      startUnix: startUnix,
      endUnix: endUnix,
    );
    final budget = SentrySyncInstrumentation.timeoutForWindow(
      startUnix: startUnix,
      endUnix: endUnix,
    );
    final parent = Sentry.getSpan();
    final span = SentrySyncInstrumentation.startChild(
      parent,
      SentrySyncInstrumentation.nameWorkouts,
    );
    span?.setTag('window', window);
    FosHuaweiLog.i(
      'syncWorkouts window=[$startUnix,$endUnix]',
      op: 'sync',
    );
    try {
      var abandoned = false;
      final map = await SentrySyncInstrumentation.invokeWithTimeout(
        future: _channel.syncWorkouts(
          startUnix: startUnix,
          endUnix: endUnix,
        ),
        timeout: budget,
        channel: 'syncWorkouts',
        onAbandoned: () {
          abandoned = true;
          return <String, dynamic>{
            'status': 'stuck',
            'message': 'Sync abandoned — channel timed out',
            'workouts': <dynamic>[],
          };
        },
      );
      final result = WorkoutSyncResult.fromMap(map);
      await SentrySyncInstrumentation.finishWithStatus(
        span,
        status: abandoned ? 'abandoned' : result.status.name,
        count: result.workouts.length,
      );
      return result;
    } on PlatformException catch (e) {
      FosHuaweiLog.e('syncWorkouts failed', error: e, op: 'sync');
      await SentrySyncInstrumentation.finishWithStatus(
        span,
        status: 'error',
      );
      return WorkoutSyncResult(
        status: WorkoutSyncStatus.error,
        // Safe short reason only — never forward raw protocol/hex details.
        message: e.code,
        workouts: const [],
      );
    } finally {
      _syncInFlight = false;
    }
  }

  /// Activity Sync (sleep + whole-day HR). Shares single-flight with workouts.
  Future<ActivitySyncResult> syncActivity({
    int? startUnix,
    int? endUnix,
    bool skipTruSleepSoft = false,
    bool skipAutoHrSoft = false,
  }) async {
    if (_syncInFlight) {
      return const ActivitySyncResult(
        status: ActivitySyncStatus.busy,
        message: 'Another Sync is already in progress',
      );
    }
    if (!sessionReady) {
      FosHuaweiLog.w(
        'syncActivity rejected — linkState=$state',
        op: 'sync',
      );
      return const ActivitySyncResult(
        status: ActivitySyncStatus.notReady,
        message: 'Connect and authenticate first',
      );
    }
    final end = endUnix ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final start = startUnix ??
        end - activityWindowDays * 24 * 60 * 60;
    _syncInFlight = true;
    final window = SentrySyncInstrumentation.windowClass(
      startUnix: start,
      endUnix: end,
    );
    final budget = SentrySyncInstrumentation.timeoutForWindow(
      startUnix: start,
      endUnix: end,
    );
    final parent = Sentry.getSpan();
    final span = SentrySyncInstrumentation.startChild(
      parent,
      SentrySyncInstrumentation.nameVitals,
    );
    span?.setTag('window', window);
    FosHuaweiLog.i(
      'syncActivity window=[$start,$end] (${activityWindowDays}d)',
      op: 'sync',
    );
    try {
      var abandoned = false;
      final map = await SentrySyncInstrumentation.invokeWithTimeout(
        future: _channel.syncActivity(
          startUnix: start,
          endUnix: end,
          skipTruSleepSoft: skipTruSleepSoft,
          skipAutoHrSoft: skipAutoHrSoft,
        ),
        timeout: budget,
        channel: 'syncActivity',
        onAbandoned: () {
          abandoned = true;
          return <String, dynamic>{
            'status': 'stuck',
            'message': 'Sync abandoned — channel timed out',
          };
        },
      );
      final result = ActivitySyncResult.fromMap(map);
      final partial = result.status == ActivitySyncStatus.partialBatch ||
          result.status == ActivitySyncStatus.stuck;
      await SentrySyncInstrumentation.finishWithStatus(
        span,
        status: abandoned ? 'abandoned' : result.status.name,
        partial: partial,
      );
      return result;
    } on PlatformException catch (e) {
      FosHuaweiLog.e('syncActivity failed', error: e, op: 'sync');
      await SentrySyncInstrumentation.finishWithStatus(
        span,
        status: 'error',
      );
      return ActivitySyncResult(
        status: ActivitySyncStatus.error,
        message: e.code,
      );
    } finally {
      _syncInFlight = false;
    }
  }

  /// Explicit auto-tracking enable. Shares Sync single-flight lock.
  Future<AutoTrackingEnableResult> enableAutoTracking() async {
    if (_syncInFlight) {
      return const AutoTrackingEnableResult(
        status: AutoTrackingEnableStatus.busy,
        message: 'Another Sync is already in progress',
        overall: AutoTrackingOverall.noneArmed,
      );
    }
    if (!sessionReady) {
      FosHuaweiLog.w(
        'enableAutoTracking rejected — linkState=$state',
        op: 'enable',
      );
      return const AutoTrackingEnableResult(
        status: AutoTrackingEnableStatus.notReady,
        message: 'Connect and authenticate first',
        overall: AutoTrackingOverall.noneArmed,
      );
    }
    _syncInFlight = true;
    FosHuaweiLog.i('enableAutoTracking start', op: 'enable');
    try {
      final map = await _channel.enableAutoTracking();
      return AutoTrackingEnableResult.fromMap(map);
    } on PlatformException catch (e) {
      FosHuaweiLog.e('enableAutoTracking failed', error: e, op: 'enable');
      return AutoTrackingEnableResult(
        status: AutoTrackingEnableStatus.error,
        message: e.message ?? 'enable failed',
        overall: AutoTrackingOverall.noneArmed,
      );
    } finally {
      _syncInFlight = false;
    }
  }

  void markGateAPassed() {
    if (_state == LinkState.gateAIncomplete || _state == LinkState.connected) {
      _setState(LinkState.connected);
    }
  }

  void markGateAIncomplete() {
    if (_state == LinkState.connected || _state == LinkState.gateAIncomplete) {
      _setState(LinkState.gateAIncomplete);
    }
  }

  void _onBtEvent(HuaweiBtEvent event) {
    switch (event) {
      case DiscoveryEvent(:final mac, :final name, :final rssi):
        FosHuaweiLog.d(
          'event discovery name=$name mac=${_redact(mac)} rssi=$rssi',
          op: 'event',
        );
        if (!HuaweiBtChannel.matchesGt5Name(name)) {
          FosHuaweiLog.d('discovery filtered (name mismatch)', op: 'event');
          return;
        }
        _discovered.removeWhere((d) => d.mac == mac);
        _discovered.add(DiscoveredDevice(mac: mac, name: name, rssi: rssi));
        FosHuaweiLog.i(
          'GT5 listed count=${_discovered.length}',
          op: 'scan',
        );
        _controller.add(DevicesUpdated(_discovered));
      case ConnectionStateEvent(:final state):
        FosHuaweiLog.i('event connection_state=$state', op: 'event');
        if (state == 'scanning') {
          _setState(LinkState.scanning);
        } else if (state == 'connecting') {
          _setState(LinkState.connecting);
        } else if (state == 'disconnected') {
          if (_state == LinkState.scanning ||
              _state == LinkState.connecting ||
              (_state != LinkState.authFailed &&
                  _state != LinkState.reconnectFailed &&
                  _state != LinkState.permissionRequired)) {
            _setState(LinkState.disconnected);
          }
        }
      case ErrorEvent(:final code, :final message):
        FosHuaweiLog.e('event error code=$code message=$message', op: 'event');
        _lastError = message;
        if (code == 'permission_denied') {
          _setState(LinkState.permissionRequired);
        } else if (code == 'scan_failed') {
          _setState(LinkState.disconnected);
        } else if (code == 'connect_failed') {
          _setState(
            _state == LinkState.connecting
                ? LinkState.reconnectFailed
                : LinkState.disconnected,
          );
        }
      case SessionStateEvent(:final state, :final message, :final hint):
        FosHuaweiLog.i(
          'event session_state=$state hint=$hint msg=$message',
          op: 'event',
        );
        _lastError = message;
        _recoveryHint = hint;
        switch (state) {
          case 'authenticating':
            _setState(LinkState.authenticating);
          case 'session_ready':
            _setState(LinkState.gateAIncomplete);
          case 'auth_failed':
            _setState(LinkState.authFailed);
          case 'bond_required':
            _setState(LinkState.bondRequired);
        }
      default:
        FosHuaweiLog.d('event other=$event', op: 'event');
    }
  }

  void _mapPlatformError(PlatformException e) {
    _lastError = e.message;
    if (e.code == 'permission_denied') {
      _setState(LinkState.permissionRequired);
    } else if (e.code == 'illegal_state') {
      _setState(LinkState.disconnected);
    } else {
      _setState(LinkState.authFailed);
    }
  }

  void _setState(LinkState next) {
    if (_state == next) {
      FosHuaweiLog.d('state unchanged → $next', op: 'state');
      return;
    }
    FosHuaweiLog.i('state $_state → $next', op: 'state');
    _state = next;
    _controller.add(LinkStateChanged(next));
    unawaited(SentrySyncInstrumentation.addLinkStateBreadcrumb(next.name));
  }

  static String _redact(String mac) {
    final parts = mac.split(':');
    if (parts.length < 3) return '••:••:••';
    return '••:••:••:${parts.sublist(parts.length - 3).join(':')}';
  }
}

enum LinkState {
  disconnected,
  permissionRequired,
  scanning,
  connecting,
  authenticating,
  authFailed,
  bondRequired,
  reconnectFailed,
  gateAIncomplete,
  connected,
}

class DiscoveredDevice {
  const DiscoveredDevice({
    required this.mac,
    required this.name,
    this.rssi,
  });
  final String mac;
  final String name;
  final int? rssi;
}

sealed class HuaweiLinkEvent {
  const HuaweiLinkEvent();
}

final class LinkStateChanged extends HuaweiLinkEvent {
  const LinkStateChanged(this.state);
  final LinkState state;
}

final class DevicesUpdated extends HuaweiLinkEvent {
  const DevicesUpdated(this.devices);
  final List<DiscoveredDevice> devices;
}

enum WorkoutSyncStatus { ok, empty, stuck, notReady, error, busy, partialBatch }

enum ActivitySyncStatus {
  ok,
  empty,
  partialBatch,
  stuck,
  notReady,
  error,
  busy,
}

/// One message-path sleep stage block (timestamp + duration + wire type).
class SleepStageSummary {
  const SleepStageSummary({
    required this.timestampUnix,
    required this.durationMin,
    this.wireType,
  });

  final int timestampUnix;
  final int durationMin;
  final int? wireType;

  factory SleepStageSummary.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    return SleepStageSummary(
      timestampUnix: asInt(map['timestampUnix']) ?? 0,
      durationMin: asInt(map['durationMin']) ?? 0,
      wireType: asInt(map['wireType']),
    );
  }

  Map<String, dynamic> toJson() => {
        'timestampUnix': timestampUnix,
        'durationMin': durationMin,
        if (wireType != null) 'wireType': wireType,
      };
}

class SleepSessionSummary {
  const SleepSessionSummary({
    required this.beginUnix,
    required this.endUnix,
    this.wireType,
    this.stages = const [],
  });

  final int beginUnix;
  final int endUnix;
  final int? wireType;

  /// Ordered stage blocks from Sync channel. Prefs store lean begin/end only;
  /// stages live in side-files under `vitals/sleep_stages`.
  final List<SleepStageSummary> stages;

  int get durationSec => (endUnix - beginUnix).clamp(0, 1 << 31);

  /// Stable merge / side-file key (begin:end:wireType).
  String get mergeKey => '$beginUnix:$endUnix:${wireType ?? ''}';

  factory SleepSessionSummary.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    final rawStages = map['stages'];
    final stages = <SleepStageSummary>[];
    if (rawStages is List) {
      for (final item in rawStages) {
        if (item is Map) {
          final stage =
              SleepStageSummary.fromMap(Map<String, dynamic>.from(item));
          if (stage.timestampUnix > 0 && stage.durationMin > 0) {
            stages.add(stage);
          }
        }
      }
    }
    return SleepSessionSummary(
      beginUnix: asInt(map['beginUnix']) ?? 0,
      endUnix: asInt(map['endUnix']) ?? 0,
      wireType: asInt(map['wireType']),
      stages: stages,
    );
  }

  /// Lean prefs payload — stages persist via side-files, not prefs JSON.
  Map<String, dynamic> toJson() => {
        'beginUnix': beginUnix,
        'endUnix': endUnix,
        if (wireType != null) 'wireType': wireType,
      };

  Map<String, dynamic> toJsonWithStages() => {
        ...toJson(),
        'stages': stages.map((s) => s.toJson()).toList(),
      };
}

class DailyHrSample {
  const DailyHrSample({
    required this.timestampUnix,
    required this.bpm,
  });

  final int timestampUnix;
  final int bpm;

  factory DailyHrSample.fromMap(Map<String, dynamic> map) {
    int asInt(Object? v) => v == null ? 0 : (v as num).toInt();
    return DailyHrSample(
      timestampUnix: asInt(map['timestampUnix']),
      bpm: asInt(map['bpm']),
    );
  }

  Map<String, dynamic> toJson() => {
        'timestampUnix': timestampUnix,
        'bpm': bpm,
      };
}

class DailyHrDaySummary {
  const DailyHrDaySummary({
    required this.dayKey,
    required this.minBpm,
    required this.avgBpm,
    required this.maxBpm,
    required this.sampleCount,
  });

  /// Local calendar day `yyyy-MM-dd`.
  final String dayKey;
  final int minBpm;
  final int avgBpm;
  final int maxBpm;
  final int sampleCount;

  factory DailyHrDaySummary.fromMap(Map<String, dynamic> map) {
    int asInt(Object? v) => v == null ? 0 : (v as num).toInt();
    return DailyHrDaySummary(
      dayKey: map['dayKey'] as String? ?? '',
      minBpm: asInt(map['minBpm']),
      avgBpm: asInt(map['avgBpm']),
      maxBpm: asInt(map['maxBpm']),
      sampleCount: asInt(map['sampleCount']),
    );
  }

  Map<String, dynamic> toJson() => {
        'dayKey': dayKey,
        'minBpm': minBpm,
        'avgBpm': avgBpm,
        'maxBpm': maxBpm,
        'sampleCount': sampleCount,
      };
}

/// FitnessTotals day rollup from activity Sync (`0x07:0x03`).
///
/// Field map is capture-gated / provisional — see wire-spec FitnessTotals section.
class FitnessTotalsDay {
  const FitnessTotalsDay({
    required this.dayKey,
    required this.dayStartUnix,
    required this.calories,
    required this.steps,
    required this.exerciseDurationSec,
  });

  /// Local calendar day `yyyy-MM-dd`.
  final String dayKey;
  final int dayStartUnix;
  final int calories;
  final int steps;

  /// Raw wire `0x07` (channel name retained). **Not** watch exercise minutes —
  /// Home workout time uses today's workout-sum until a duration tag is owned.
  final int exerciseDurationSec;

  factory FitnessTotalsDay.fromMap(Map<String, dynamic> map) {
    int asInt(Object? v) => v == null ? 0 : (v as num).toInt();
    return FitnessTotalsDay(
      dayKey: map['dayKey'] as String? ?? '',
      dayStartUnix: asInt(map['dayStartUnix']),
      calories: asInt(map['calories']),
      steps: asInt(map['steps']),
      exerciseDurationSec: asInt(map['exerciseDurationSec']),
    );
  }

  Map<String, dynamic> toJson() => {
        'dayKey': dayKey,
        'dayStartUnix': dayStartUnix,
        'calories': calories,
        'steps': steps,
        'exerciseDurationSec': exerciseDurationSec,
      };
}

enum AutoTrackingEnableStatus { ok, busy, notReady, error }

enum AutoTrackingOverall { allArmed, partial, noneArmed }

class AutoTrackingFeatureOutcome {
  const AutoTrackingFeatureOutcome({
    required this.id,
    required this.outcome,
    this.resultCode,
  });

  final String id;
  /// armed | skipped | failed | timed_out
  final String outcome;
  final int? resultCode;

  factory AutoTrackingFeatureOutcome.fromMap(Map<String, dynamic> map) {
    return AutoTrackingFeatureOutcome(
      id: map['id'] as String? ?? '',
      outcome: map['outcome'] as String? ?? 'failed',
      resultCode: (map['resultCode'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'outcome': outcome,
        if (resultCode != null) 'resultCode': resultCode,
      };
}

class AutoTrackingEnableResult {
  const AutoTrackingEnableResult({
    required this.status,
    required this.overall,
    this.message,
    this.features = const [],
    this.completedAt,
  });

  final AutoTrackingEnableStatus status;
  final AutoTrackingOverall overall;
  final String? message;
  final List<AutoTrackingFeatureOutcome> features;
  final int? completedAt;

  String? outcomeFor(String id) {
    for (final f in features) {
      if (f.id == id) return f.outcome;
    }
    return null;
  }

  bool get hasArmedAutoHr => outcomeFor('auto_hr') == 'armed';

  factory AutoTrackingEnableResult.fromMap(Map<String, dynamic> map) {
    final statusStr = map['status'] as String? ?? 'error';
    final status = switch (statusStr) {
      'ok' => AutoTrackingEnableStatus.ok,
      'busy' => AutoTrackingEnableStatus.busy,
      'not_ready' => AutoTrackingEnableStatus.notReady,
      _ => AutoTrackingEnableStatus.error,
    };
    final overallStr = map['overall'] as String? ?? 'none_armed';
    final overall = switch (overallStr) {
      'all_armed' => AutoTrackingOverall.allArmed,
      'partial' => AutoTrackingOverall.partial,
      _ => AutoTrackingOverall.noneArmed,
    };
    final features = <AutoTrackingFeatureOutcome>[];
    final raw = map['features'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          features.add(
            AutoTrackingFeatureOutcome.fromMap(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }
    return AutoTrackingEnableResult(
      status: status,
      overall: overall,
      message: map['message'] as String?,
      features: features,
      completedAt: (map['completedAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toPrefsJson() => {
        'overall': switch (overall) {
          AutoTrackingOverall.allArmed => 'all_armed',
          AutoTrackingOverall.partial => 'partial',
          AutoTrackingOverall.noneArmed => 'none_armed',
        },
        'features': features.map((f) => f.toJson()).toList(),
        if (completedAt != null) 'completedAt': completedAt,
      };

  /// Fail-closed allowlisted decode for prefs SoT.
  static AutoTrackingEnableResult? tryParsePrefs(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      // Reject series-shaped / bulky payloads.
      for (final key in map.keys) {
        if (key != 'overall' &&
            key != 'features' &&
            key != 'completedAt') {
          return null;
        }
      }
      final featuresRaw = map['features'];
      if (featuresRaw is! List) return null;
      final features = <AutoTrackingFeatureOutcome>[];
      for (final item in featuresRaw) {
        if (item is! Map) return null;
        final f = Map<String, dynamic>.from(item);
        final id = f['id'] as String?;
        final outcome = f['outcome'] as String?;
        if (id == null || outcome == null) return null;
        if (f.keys.any((k) => k != 'id' && k != 'outcome' && k != 'resultCode')) {
          return null;
        }
        features.add(
          AutoTrackingFeatureOutcome(
            id: id,
            outcome: outcome,
            resultCode: (f['resultCode'] as num?)?.toInt(),
          ),
        );
      }
      final overallStr = map['overall'] as String? ?? 'none_armed';
      return AutoTrackingEnableResult(
        status: AutoTrackingEnableStatus.ok,
        overall: switch (overallStr) {
          'all_armed' => AutoTrackingOverall.allArmed,
          'partial' => AutoTrackingOverall.partial,
          _ => AutoTrackingOverall.noneArmed,
        },
        features: features,
        completedAt: (map['completedAt'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

class ActivitySyncResult {
  const ActivitySyncResult({
    required this.status,
    this.message,
    this.sleepSessions = const [],
    this.dailyHrSamples = const [],
    this.fitnessTotals = const [],
    this.completedContainers = const {},
    this.enableSkipped = false,
  });

  final ActivitySyncStatus status;
  final String? message;
  final List<SleepSessionSummary> sleepSessions;
  final List<DailyHrSample> dailyHrSamples;
  final List<FitnessTotalsDay> fitnessTotals;
  final Set<String> completedContainers;
  final bool enableSkipped;

  factory ActivitySyncResult.fromMap(Map<String, dynamic> map) {
    final statusStr = map['status'] as String? ?? 'error';
    final status = switch (statusStr) {
      'ok' => ActivitySyncStatus.ok,
      'empty' => ActivitySyncStatus.empty,
      'partial_batch' => ActivitySyncStatus.partialBatch,
      'stuck' => ActivitySyncStatus.stuck,
      'not_ready' => ActivitySyncStatus.notReady,
      'busy' => ActivitySyncStatus.busy,
      _ => ActivitySyncStatus.error,
    };
    final sleep = <SleepSessionSummary>[];
    final rawSleep = map['sleepSessions'];
    if (rawSleep is List) {
      for (final item in rawSleep) {
        if (item is Map) {
          sleep.add(
            SleepSessionSummary.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final hr = <DailyHrSample>[];
    final rawHr = map['dailyHrSamples'];
    if (rawHr is List) {
      for (final item in rawHr) {
        if (item is Map) {
          hr.add(DailyHrSample.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }
    final totals = <FitnessTotalsDay>[];
    final rawTotals = map['fitnessTotals'];
    if (rawTotals is List) {
      for (final item in rawTotals) {
        if (item is Map) {
          final day = FitnessTotalsDay.fromMap(Map<String, dynamic>.from(item));
          if (day.dayKey.isNotEmpty) totals.add(day);
        }
      }
    }
    final completed = <String>{};
    final rawCompleted = map['completedContainers'];
    if (rawCompleted is List) {
      for (final item in rawCompleted) {
        if (item is String) completed.add(item);
      }
    }
    return ActivitySyncResult(
      status: status,
      message: map['message'] as String?,
      sleepSessions: sleep,
      dailyHrSamples: hr,
      fitnessTotals: totals,
      completedContainers: completed,
      enableSkipped: map['enableSkipped'] as bool? ?? false,
    );
  }
}

class EnrichmentTagRef {
  const EnrichmentTagRef({required this.id, required this.len});

  final int id;
  final int len;

  factory EnrichmentTagRef.fromMap(Map<String, dynamic> map) {
    int asInt(Object? v) => v == null ? 0 : (v as num).toInt();
    return EnrichmentTagRef(
      id: asInt(map['id']),
      len: asInt(map['len']),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'len': len};
}

class WorkoutSegment {
  const WorkoutSegment({
    required this.index,
    this.distanceM,
    this.durationSec,
    this.swimType,
    this.style,
    this.strokes,
    this.avgSwolf,
    this.paceSecPer100m,
    this.tags,
  });

  final int index;
  final int? distanceM;
  final int? durationSec;
  final int? swimType;
  final int? style;
  final int? strokes;
  final int? avgSwolf;
  final int? paceSecPer100m;
  final List<EnrichmentTagRef>? tags;

  factory WorkoutSegment.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    List<EnrichmentTagRef>? tags;
    final rawTags = map['tags'];
    if (rawTags is List) {
      tags = rawTags
          .whereType<Map>()
          .map((e) => EnrichmentTagRef.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return WorkoutSegment(
      index: asInt(map['index']) ?? 0,
      distanceM: asInt(map['distanceM']),
      durationSec: asInt(map['durationSec']),
      swimType: asInt(map['swimType']),
      style: asInt(map['style']),
      strokes: asInt(map['strokes']),
      avgSwolf: asInt(map['avgSwolf']),
      paceSecPer100m: asInt(map['paceSecPer100m']),
      tags: tags,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        if (distanceM != null) 'distanceM': distanceM,
        if (durationSec != null) 'durationSec': durationSec,
        if (swimType != null) 'swimType': swimType,
        if (style != null) 'style': style,
        if (strokes != null) 'strokes': strokes,
        if (avgSwolf != null) 'avgSwolf': avgSwolf,
        if (paceSecPer100m != null) 'paceSecPer100m': paceSecPer100m,
        if (tags != null && tags!.isNotEmpty)
          'tags': tags!.map((t) => t.toJson()).toList(),
      };
}

class WorkoutSummary {
  const WorkoutSummary({
    required this.number,
    required this.startTime,
    required this.endTime,
    required this.durationSec,
    required this.type,
    this.calories,
    this.distanceM,
    this.steps,
    this.dataCount,
    this.paceCount,
    this.segmentsCount,
    this.sampleCount,
    this.enrichmentStatus,
    this.hrMin,
    this.hrMax,
    this.hrPeak,
    this.swimType,
    this.strokes,
    this.strokeRate,
    this.avgSwolf,
    this.sessionFlag,
    this.poolLength,
    this.laps,
    this.enrichmentTags,
    this.segments,
  });

  final int number;
  final int startTime;
  final int endTime;
  final int durationSec;
  final int type;
  final int? calories;
  final int? distanceM;
  final int? steps;
  final int? dataCount;
  final int? paceCount;
  final int? segmentsCount;
  final int? sampleCount;
  final String? enrichmentStatus;
  final int? hrMin;
  final int? hrMax;
  final int? hrPeak;
  final int? swimType;
  final int? strokes;
  final int? strokeRate;
  final int? avgSwolf;

  /// Optional one-line teaser for the list (e.g. pace decay). Never a chart.
  final String? sessionFlag;
  final int? poolLength;
  final int? laps;
  final List<EnrichmentTagRef>? enrichmentTags;
  final List<WorkoutSegment>? segments;

  factory WorkoutSummary.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    List<EnrichmentTagRef>? tags;
    final rawTags = map['enrichmentTags'];
    if (rawTags is List) {
      tags = rawTags
          .whereType<Map>()
          .map((e) => EnrichmentTagRef.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    List<WorkoutSegment>? segments;
    final rawSegments = map['segments'];
    if (rawSegments is List) {
      segments = rawSegments
          .whereType<Map>()
          .map((e) => WorkoutSegment.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return WorkoutSummary(
      number: asInt(map['number']) ?? 0,
      startTime: asInt(map['startTime']) ?? 0,
      endTime: asInt(map['endTime']) ?? 0,
      durationSec: asInt(map['durationSec']) ?? 0,
      type: asInt(map['type']) ?? 0,
      calories: asInt(map['calories']),
      distanceM: asInt(map['distanceM']),
      steps: asInt(map['steps']),
      dataCount: asInt(map['dataCount']),
      paceCount: asInt(map['paceCount']),
      segmentsCount: asInt(map['segmentsCount']),
      sampleCount: asInt(map['sampleCount']),
      enrichmentStatus: map['enrichmentStatus'] as String?,
      hrMin: asInt(map['hrMin']),
      hrMax: asInt(map['hrMax']),
      hrPeak: asInt(map['hrPeak']),
      swimType: asInt(map['swimType']),
      strokes: asInt(map['strokes']),
      strokeRate: asInt(map['strokeRate']),
      avgSwolf: asInt(map['avgSwolf']),
      sessionFlag: map['sessionFlag'] as String?,
      poolLength: asInt(map['poolLength']),
      laps: asInt(map['laps']),
      enrichmentTags: tags,
      segments: segments,
    );
  }

  Map<String, dynamic> toJson() => {
        'number': number,
        'startTime': startTime,
        'endTime': endTime,
        'durationSec': durationSec,
        'type': type,
        if (calories != null) 'calories': calories,
        if (distanceM != null) 'distanceM': distanceM,
        if (steps != null) 'steps': steps,
        if (dataCount != null) 'dataCount': dataCount,
        if (paceCount != null) 'paceCount': paceCount,
        if (segmentsCount != null) 'segmentsCount': segmentsCount,
        if (sampleCount != null) 'sampleCount': sampleCount,
        if (enrichmentStatus != null) 'enrichmentStatus': enrichmentStatus,
        if (hrMin != null) 'hrMin': hrMin,
        if (hrMax != null) 'hrMax': hrMax,
        if (hrPeak != null) 'hrPeak': hrPeak,
        if (swimType != null) 'swimType': swimType,
        if (strokes != null) 'strokes': strokes,
        if (strokeRate != null) 'strokeRate': strokeRate,
        if (avgSwolf != null) 'avgSwolf': avgSwolf,
        if (sessionFlag != null) 'sessionFlag': sessionFlag,
        if (poolLength != null) 'poolLength': poolLength,
        if (laps != null) 'laps': laps,
        if (enrichmentTags != null && enrichmentTags!.isNotEmpty)
          'enrichmentTags': enrichmentTags!.map((t) => t.toJson()).toList(),
        if (segments != null && segments!.isNotEmpty)
          'segments': segments!.map((s) => s.toJson()).toList(),
      };
}

class WorkoutSyncResult {
  const WorkoutSyncResult({
    required this.status,
    required this.workouts,
    this.message,
  });

  final WorkoutSyncStatus status;
  final List<WorkoutSummary> workouts;
  final String? message;

  factory WorkoutSyncResult.fromMap(Map<String, dynamic> map) {
    final statusStr = map['status'] as String? ?? 'error';
    final status = switch (statusStr) {
      'ok' => WorkoutSyncStatus.ok,
      'empty' => WorkoutSyncStatus.empty,
      'stuck' => WorkoutSyncStatus.stuck,
      'not_ready' => WorkoutSyncStatus.notReady,
      'busy' => WorkoutSyncStatus.busy,
      'partial_batch' => WorkoutSyncStatus.partialBatch,
      _ => WorkoutSyncStatus.error,
    };
    final rawList = map['workouts'];
    final workouts = <WorkoutSummary>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          workouts.add(
            WorkoutSummary.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return WorkoutSyncResult(
      status: status,
      workouts: workouts,
      message: map['message'] as String?,
    );
  }
}
