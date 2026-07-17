import 'dart:async';

import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:flutter/foundation.dart';
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

  LinkState get state => _state;
  String? get lastError => _lastError;
  String? get recoveryHint => _recoveryHint;
  List<DiscoveredDevice> get discovered => List.unmodifiable(_discovered);
  Stream<HuaweiLinkEvent> get events => _controller.stream;

  Future<void> start() async {
    await _sub?.cancel();
    _sub = _channel.events().listen(_onBtEvent);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }

  Future<bool> ensurePermissions() async {
    final ok = await _channel.checkPermissions();
    if (ok) return true;
    final granted = await _channel.requestPermissions();
    if (!granted) {
      _setState(LinkState.permissionRequired);
    }
    return granted;
  }

  Future<void> startScan() async {
    final permitted = await ensurePermissions();
    if (!permitted) return;

    final adapter = await _channel.getAdapterState();
    if (adapter != 'on') {
      _lastError = 'Bluetooth adapter is off';
      _setState(LinkState.disconnected);
      return;
    }

    _discovered.clear();
    _setState(LinkState.scanning);
    try {
      await _channel.startBleDiscovery();
    } on PlatformException catch (e) {
      _mapPlatformError(e);
    }
  }

  Future<void> stopScan() => _channel.stopBleDiscovery();

  Future<void> connectAndAuthenticate(String mac) async {
    final permitted = await ensurePermissions();
    if (!permitted) return;

    try {
      await _channel.stopBleDiscovery();
      _setState(LinkState.connecting);
      final connected = _waitForConnectionState('connected');
      await _channel.connect(mac: mac);
      final ok = await connected.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      if (!ok) {
        _lastError = 'RFCOMM connect timed out';
        _setState(LinkState.reconnectFailed);
        return;
      }

      _setState(LinkState.authenticating);
      final outcome = await _channel.authenticate();
      if (outcome == 'Ready') {
        _setState(LinkState.gateAIncomplete);
      } else {
        _setState(LinkState.authFailed);
      }
    } on PlatformException catch (e) {
      _mapPlatformError(e);
    }
  }

  /// Cold-start reconnect for a remembered MAC (no scan).
  Future<void> reconnect(String mac) async {
    final permitted = await ensurePermissions();
    if (!permitted) return;

    final adapter = await _channel.getAdapterState();
    if (adapter != 'on') {
      _lastError = 'Bluetooth adapter is off — waiting';
      _setState(LinkState.disconnected);
      return;
    }

    final hasSecrets = await _channel.hasSecrets();
    if (!hasSecrets) {
      _lastError = 'Remembered device is missing secrets — re-pair required';
      _recoveryHint = 'r11_repair';
      _setState(LinkState.authFailed);
      return;
    }

    try {
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
      if (outcome == 'Ready') {
        _setState(LinkState.gateAIncomplete);
      } else {
        _lastError = 'Reconnect authentication failed';
        _setState(LinkState.reconnectFailed);
      }
    } on PlatformException catch (e) {
      _lastError = e.message;
      if (e.code == 'illegal_state' &&
          (e.message ?? '').toLowerCase().contains('bond')) {
        _setState(LinkState.bondRequired);
      } else {
        _setState(LinkState.reconnectFailed);
      }
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

  Future<void> setAuthKey(String userId) => _channel.setAuthKey(userId);

  Future<bool> hasSecrets() => _channel.hasSecrets();

  Future<void> clearSecrets() => _channel.clearSecrets();

  Future<void> disconnect() async {
    await _channel.disconnect();
    _setState(LinkState.disconnected);
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
        if (!HuaweiBtChannel.matchesGt5Name(name)) return;
        _discovered.removeWhere((d) => d.mac == mac);
        _discovered.add(DiscoveredDevice(mac: mac, name: name, rssi: rssi));
        _controller.add(DevicesUpdated(_discovered));
      case ConnectionStateEvent(:final state):
        if (state == 'scanning') {
          _setState(LinkState.scanning);
        } else if (state == 'connecting') {
          _setState(LinkState.connecting);
        } else if (state == 'disconnected' &&
            _state != LinkState.authFailed &&
            _state != LinkState.reconnectFailed &&
            _state != LinkState.permissionRequired) {
          _setState(LinkState.disconnected);
        }
      case ErrorEvent(:final code, :final message):
        _lastError = message;
        if (code == 'permission_denied') {
          _setState(LinkState.permissionRequired);
        } else if (code == 'connect_failed') {
          _setState(
            _state == LinkState.connecting
                ? LinkState.reconnectFailed
                : LinkState.disconnected,
          );
        }
      case SessionStateEvent(:final state, :final message, :final hint):
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
        break;
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
    _state = next;
    _controller.add(LinkStateChanged(next));
    if (kDebugMode) {
      debugPrint('HuaweiLink → $next');
    }
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
