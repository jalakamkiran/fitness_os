import 'dart:async';

import 'package:fitness_os/core/huawei/fos_huawei_log.dart';
import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:flutter/services.dart';

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
    FosHuaweiLog.i(
      'syncWorkouts window=[$startUnix,$endUnix]',
      op: 'sync',
    );
    try {
      final map = await _channel.syncWorkouts(
        startUnix: startUnix,
        endUnix: endUnix,
      );
      return WorkoutSyncResult.fromMap(map);
    } on PlatformException catch (e) {
      FosHuaweiLog.e('syncWorkouts failed', error: e, op: 'sync');
      return WorkoutSyncResult(
        status: WorkoutSyncStatus.error,
        message: e.message ?? 'sync failed',
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
  }) async {
    if (_syncInFlight) {
      return const ActivitySyncResult(
        status: ActivitySyncStatus.busy,
        message: 'Another Sync is already in progress',
      );
    }
    if (state != LinkState.connected &&
        state != LinkState.gateAIncomplete) {
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
    FosHuaweiLog.i(
      'syncActivity window=[$start,$end] (${activityWindowDays}d)',
      op: 'sync',
    );
    try {
      final map = await _channel.syncActivity(
        startUnix: start,
        endUnix: end,
      );
      return ActivitySyncResult.fromMap(map);
    } on PlatformException catch (e) {
      FosHuaweiLog.e('syncActivity failed', error: e, op: 'sync');
      return ActivitySyncResult(
        status: ActivitySyncStatus.error,
        message: e.message ?? 'sync failed',
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

class SleepSessionSummary {
  const SleepSessionSummary({
    required this.beginUnix,
    required this.endUnix,
    this.wireType,
  });

  final int beginUnix;
  final int endUnix;
  final int? wireType;

  int get durationSec => (endUnix - beginUnix).clamp(0, 1 << 31);

  factory SleepSessionSummary.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    return SleepSessionSummary(
      beginUnix: asInt(map['beginUnix']) ?? 0,
      endUnix: asInt(map['endUnix']) ?? 0,
      wireType: asInt(map['wireType']),
    );
  }

  Map<String, dynamic> toJson() => {
        'beginUnix': beginUnix,
        'endUnix': endUnix,
        if (wireType != null) 'wireType': wireType,
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

class ActivitySyncResult {
  const ActivitySyncResult({
    required this.status,
    this.message,
    this.sleepSessions = const [],
    this.dailyHrSamples = const [],
    this.completedContainers = const {},
    this.enableSkipped = false,
  });

  final ActivitySyncStatus status;
  final String? message;
  final List<SleepSessionSummary> sleepSessions;
  final List<DailyHrSample> dailyHrSamples;
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
      completedContainers: completed,
      enableSkipped: map['enableSkipped'] as bool? ?? false,
    );
  }
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
  });

  final int number;
  final int startTime;
  final int endTime;
  final int durationSec;
  final int type;
  final int? calories;
  final int? distanceM;
  final int? steps;

  factory WorkoutSummary.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    return WorkoutSummary(
      number: asInt(map['number']) ?? 0,
      startTime: asInt(map['startTime']) ?? 0,
      endTime: asInt(map['endTime']) ?? 0,
      durationSec: asInt(map['durationSec']) ?? 0,
      type: asInt(map['type']) ?? 0,
      calories: asInt(map['calories']),
      distanceM: asInt(map['distanceM']),
      steps: asInt(map['steps']),
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
