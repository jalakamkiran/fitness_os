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

  Future<void> liftConfigure({required bool enabled}) =>
      _method.invokeMethod<void>('liftConfigure', {'enabled': enabled});

  Future<void> liftSetBuildFlag({required bool enabled}) =>
      _method.invokeMethod<void>('liftSetBuildFlag', {'enabled': enabled});

  Future<Map<String, dynamic>> liftEnableWatchNotifications() async {
    final raw =
        await _method.invokeMethod<dynamic>('liftEnableWatchNotifications');
    return Map<String, dynamic>.from(raw as Map? ?? {});
  }

  Future<Map<String, dynamic>> liftCapabilities({required bool enabled}) async {
    final raw = await _method.invokeMethod<dynamic>('liftCapabilities', {
      'enabled': enabled,
    });
    return Map<String, dynamic>.from(raw as Map? ?? {});
  }

  Future<Map<String, dynamic>> liftSendTestNotification({
    required bool enabled,
    required String title,
    required String sender,
    required String body,
    required bool withReplyKey,
    required int type,
    required String key,
    String? category,
    String? sourceAppId,
  }) async {
    final raw = await _method.invokeMethod<dynamic>(
      'liftSendTestNotification',
      {
        'enabled': enabled,
        'title': title,
        'sender': sender,
        'body': body,
        'withReplyKey': withReplyKey,
        'type': type,
        'key': key,
        'category': category,
        'sourceAppId': sourceAppId,
      },
    );
    return Map<String, dynamic>.from(raw as Map? ?? {});
  }

  Future<Map<String, dynamic>> liftSendPlainTestNotification({
    required bool enabled,
    required String title,
    required String body,
    required int type,
    String? sourceAppId,
  }) async {
    final raw = await _method.invokeMethod<dynamic>(
      'liftSendPlainTestNotification',
      {
        'enabled': enabled,
        'title': title,
        'body': body,
        'type': type,
        'sourceAppId': sourceAppId,
      },
    );
    return Map<String, dynamic>.from(raw as Map? ?? {});
  }

  Future<Map<String, dynamic>> liftRemove({required bool enabled}) async {
    final raw =
        await _method.invokeMethod<dynamic>('liftRemove', {'enabled': enabled});
    return Map<String, dynamic>.from(raw as Map? ?? {});
  }

  Future<Map<String, dynamic>> liftQueryQuickReplies({
    required bool enabled,
  }) async {
    final raw = await _method.invokeMethod<dynamic>(
      'liftQueryQuickReplies',
      {'enabled': enabled},
    );
    return Map<String, dynamic>.from(raw as Map? ?? {});
  }

  Future<void> liftStartForeground({
    required String title,
    required String body,
  }) =>
      _method.invokeMethod<void>('liftStartForeground', {
        'title': title,
        'body': body,
      });

  Future<void> liftStopForeground() =>
      _method.invokeMethod<void>('liftStopForeground');

  Future<Map<String, dynamic>> liftSetQuickReplies({
    required bool enabled,
    required List<String> replies,
  }) async {
    final raw = await _method.invokeMethod<dynamic>(
      'liftSetQuickReplies',
      {'enabled': enabled, 'replies': replies},
    );
    return Map<String, dynamic>.from(raw as Map? ?? {});
  }

  /// Gate B: native Count→Totals. Returns `{status, message?, workouts: [...]}`.
  ///
  /// [enrichStartUnix] gates Data/Pace/Swim (defaults to [startUnix] when omitted).
  Future<Map<String, dynamic>> syncWorkouts({
    required int startUnix,
    required int endUnix,
    int? enrichStartUnix,
  }) async {
    final raw = await _method.invokeMethod<dynamic>('syncWorkouts', {
      'startUnix': startUnix,
      'endUnix': endUnix,
      if (enrichStartUnix != null) 'enrichStartUnix': enrichStartUnix,
    });
    return Map<String, dynamic>.from(raw as Map? ?? const {});
  }

  /// Activity Sync: FitnessData sleep + daily HR.
  /// Default window is last 14 local days when native omits bounds.
  Future<Map<String, dynamic>> syncActivity({
    required int startUnix,
    required int endUnix,
    bool skipTruSleepSoft = false,
    bool skipAutoHrSoft = false,
  }) async {
    final raw = await _method.invokeMethod<dynamic>('syncActivity', {
      'startUnix': startUnix,
      'endUnix': endUnix,
      'skipTruSleepSoft': skipTruSleepSoft,
      'skipAutoHrSoft': skipAutoHrSoft,
    });
    return Map<String, dynamic>.from(raw as Map? ?? const {});
  }

  /// Explicit TruSleep / auto-HR / auto-SpO2 enable batch.
  Future<Map<String, dynamic>> enableAutoTracking() async {
    final raw = await _method.invokeMethod<dynamic>('enableAutoTracking');
    return Map<String, dynamic>.from(raw as Map? ?? const {});
  }

  /// Debug-only post-Sync physio capture probe (dict / sleep_data / path-2).
  /// Never merges into product TruSleep SoT. Bound to FLAG_DEBUGGABLE on native.
  Future<Map<String, dynamic>> probePhysioCapture({
    bool includeDict = true,
    bool includeSleepData = true,
    bool includePath2Intervals = false,
    int? startUnix,
    int? endUnix,
  }) async {
    assert(kDebugMode, 'probePhysioCapture is debug-only');
    final raw = await _method.invokeMethod<dynamic>('probePhysioCapture', {
      'includeDict': includeDict,
      'includeSleepData': includeSleepData,
      'includePath2Intervals': includePath2Intervals,
      if (startUnix != null) 'startUnix': startUnix,
      if (endUnix != null) 'endUnix': endUnix,
    });
    return Map<String, dynamic>.from(raw as Map? ?? const {});
  }

  /// Debug-only: download `sleep_data.bin` and persist under app files.
  /// Never merges into product TruSleep SoT.
  Future<Map<String, dynamic>> persistSleepDataCapture({
    int? startUnix,
    int? endUnix,
  }) async {
    assert(kDebugMode, 'persistSleepDataCapture is debug-only');
    final raw = await _method.invokeMethod<dynamic>('persistSleepDataCapture', {
      if (startUnix != null) 'startUnix': startUnix,
      if (endUnix != null) 'endUnix': endUnix,
    });
    return Map<String, dynamic>.from(raw as Map? ?? const {});
  }

  /// Debug-only: download SEQUENCE_DATA SLEEP_DETAILS and persist under app files.
  /// Never merges into product TruSleep SoT.
  Future<Map<String, dynamic>> persistSleepDetailsSequenceCapture({
    int? startUnix,
    int? endUnix,
  }) async {
    assert(kDebugMode, 'persistSleepDetailsSequenceCapture is debug-only');
    final raw = await _method.invokeMethod<dynamic>(
      'persistSleepDetailsSequenceCapture',
      {
        if (startUnix != null) 'startUnix': startUnix,
        if (endUnix != null) 'endUnix': endUnix,
      },
    );
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
