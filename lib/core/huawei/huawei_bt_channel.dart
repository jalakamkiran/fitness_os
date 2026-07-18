import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Temporary U1 transport channel surface.
/// Product-facing typed session API lands in U3 (`HuaweiLink`).
class HuaweiBtChannel {
  HuaweiBtChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ??
            const MethodChannel('fitness_os/huawei_bt'),
        _events = eventChannel ??
            const EventChannel('fitness_os/huawei_bt_events');

  final MethodChannel _method;
  final EventChannel _events;

  static const huaweiSdpUuid = '82FF3820-8411-400C-B85A-55BDB32CF060';
  static const namePrefix = 'huawei watch gt 5';

  Stream<HuaweiBtEvent>? _broadcast;

  Stream<HuaweiBtEvent> events() {
    return _broadcast ??= _events
        .receiveBroadcastStream()
        .map(_mapEvent)
        .asBroadcastStream();
  }

  Future<String> getAdapterState() async {
    final state = await _method.invokeMethod<String>('getAdapterState');
    return state ?? 'unavailable';
  }

  Future<bool> checkPermissions() async {
    final ok = await _method.invokeMethod<bool>('checkPermissions');
    return ok ?? false;
  }

  Future<bool> requestPermissions() async {
    final ok = await _method.invokeMethod<bool>('requestPermissions');
    return ok ?? false;
  }

  Future<void> startBleDiscovery() =>
      _method.invokeMethod<void>('startBleDiscovery');

  Future<void> stopBleDiscovery({bool emitDisconnected = true}) =>
      _method.invokeMethod<void>('stopBleDiscovery', {
        'emitDisconnected': emitDisconnected,
      });

  Future<void> connect({
    required String mac,
    String sdpUuid = huaweiSdpUuid,
  }) {
    return _method.invokeMethod<void>('connect', {
      'mac': mac,
      'sdpUuid': sdpUuid,
    });
  }

  /// Debug-only raw byte write. Bound to BuildConfig.DEBUG on native.
  Future<void> writeDebug(Uint8List bytes) {
    assert(kDebugMode, 'writeDebug is debug-only');
    return _method.invokeMethod<void>('write', {'bytes': bytes});
  }

  Future<void> disconnect() => _method.invokeMethod<void>('disconnect');

  Future<bool?> lastSocketSecure() =>
      _method.invokeMethod<bool>('lastSocketSecure');

  Future<String> authenticate() async {
    final outcome = await _method.invokeMethod<String>('authenticate');
    return outcome ?? 'AuthFailed';
  }

  Future<void> setAuthKey(String userId) =>
      _method.invokeMethod<void>('setAuthKey', {'userId': userId});

  Future<bool> hasSecrets() async {
    final ok = await _method.invokeMethod<bool>('hasSecrets');
    return ok ?? false;
  }

  Future<void> clearSecrets() => _method.invokeMethod<void>('clearSecrets');

  /// Gate B: native Count→Totals. Returns `{status, message?, workouts: [...]}`.
  Future<Map<String, dynamic>> syncWorkouts({
    required int startUnix,
    required int endUnix,
  }) async {
    final raw = await _method.invokeMethod<dynamic>('syncWorkouts', {
      'startUnix': startUnix,
      'endUnix': endUnix,
    });
    return Map<String, dynamic>.from(raw as Map? ?? const {});
  }

  static bool matchesGt5Name(String name) {
    final n = name.toLowerCase().trim();
    return n.contains('huawei') && n.contains('gt 5');
  }

  /// Visible for unit tests.
  @visibleForTesting
  static HuaweiBtEvent mapEventForTest(dynamic raw) => _mapEvent(raw);

  static HuaweiBtEvent _mapEvent(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    final type = map['type'] as String? ?? 'unknown';
    switch (type) {
      case 'adapter_state':
        return AdapterStateEvent(map['state'] as String? ?? 'unknown');
      case 'discovery':
        return DiscoveryEvent(
          mac: map['mac'] as String? ?? '',
          name: map['name'] as String? ?? '',
          rssi: map['rssi'] as int?,
        );
      case 'connection_state':
        return ConnectionStateEvent(
          state: map['state'] as String? ?? 'unknown',
          mac: map['mac'] as String?,
          secure: map['secure'] as bool?,
        );
      case 'data':
        final bytes = map['bytes'];
        return DataEvent(
          bytes: bytes is Uint8List
              ? bytes
              : Uint8List.fromList(List<int>.from(bytes as List)),
        );
      case 'error':
        return ErrorEvent(
          code: map['code'] as String? ?? 'error',
          message: map['message'] as String? ?? 'Unknown error',
        );
      case 'session_state':
        return SessionStateEvent(
          state: map['state'] as String? ?? 'unknown',
          message: map['message'] as String?,
          hint: map['hint'] as String?,
        );
      case 'session_frame':
        return SessionFrameEvent(
          serviceId: map['serviceId'] as int? ?? 0,
          commandId: map['commandId'] as int? ?? 0,
        );
      default:
        return UnknownEvent(map);
    }
  }
}

sealed class HuaweiBtEvent {
  const HuaweiBtEvent();
}

final class AdapterStateEvent extends HuaweiBtEvent {
  const AdapterStateEvent(this.state);
  final String state;
}

final class DiscoveryEvent extends HuaweiBtEvent {
  const DiscoveryEvent({
    required this.mac,
    required this.name,
    this.rssi,
  });
  final String mac;
  final String name;
  final int? rssi;
}

final class ConnectionStateEvent extends HuaweiBtEvent {
  const ConnectionStateEvent({
    required this.state,
    this.mac,
    this.secure,
  });
  final String state;
  final String? mac;
  final bool? secure;
}

final class DataEvent extends HuaweiBtEvent {
  const DataEvent({required this.bytes});
  final Uint8List bytes;
}

final class ErrorEvent extends HuaweiBtEvent {
  const ErrorEvent({required this.code, required this.message});
  final String code;
  final String message;
}

final class UnknownEvent extends HuaweiBtEvent {
  const UnknownEvent(this.raw);
  final Map<String, dynamic> raw;
}

final class SessionStateEvent extends HuaweiBtEvent {
  const SessionStateEvent({
    required this.state,
    this.message,
    this.hint,
  });
  final String state;
  final String? message;
  final String? hint;
}

final class SessionFrameEvent extends HuaweiBtEvent {
  const SessionFrameEvent({
    required this.serviceId,
    required this.commandId,
  });
  final int serviceId;
  final int commandId;
}
