import 'dart:async';
import 'dart:convert';

import 'package:fitness_os/core/huawei/fos_huawei_log.dart';
import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:fitness_os/core/observability/sentry_config.dart';
import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';
import 'package:flutter/foundation.dart';
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
  ///
  /// [enrichStartUnix] optionally narrows Data/Pace/Swim enrich relative to
  /// Count [startUnix]. Defaults to [startUnix] when omitted.
  Future<WorkoutSyncResult> syncWorkouts({
    required int startUnix,
    required int endUnix,
    int? enrichStartUnix,
  }) async {
    if (_syncInFlight) {
      return const WorkoutSyncResult(
        status: WorkoutSyncStatus.busy,
        message: 'Another Sync is already in progress',
        workouts: [],
      );
    }
    if (!sessionReady) {
      // Force Sync often lands mid-reconnect (authenticating). Wait briefly
      // instead of soft-failing — otherwise only a later delta Sync runs and
      // older strength sessions never re-fetch Load / Recovery.
      final becameReady = await _awaitSessionReady();
      if (!becameReady) {
        FosHuaweiLog.w(
          'syncWorkouts rejected — linkState=$state',
          op: 'sync',
        );
        return WorkoutSyncResult(
          status: WorkoutSyncStatus.notReady,
          message: state == LinkState.connecting ||
                  state == LinkState.authenticating
              ? 'Watch still connecting — wait until linked, then Force Sync again'
              : 'Connect and authenticate first',
          workouts: const [],
        );
      }
    }
    _syncInFlight = true;
    final enrichFloor = enrichStartUnix ?? startUnix;
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
      'syncWorkouts window=[$startUnix,$endUnix] enrichStart=$enrichFloor',
      op: 'sync',
    );
    try {
      var abandoned = false;
      final map = await SentrySyncInstrumentation.invokeWithTimeout(
        future: _channel.syncWorkouts(
          startUnix: startUnix,
          endUnix: endUnix,
          enrichStartUnix: enrichFloor,
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
    } on PlatformException catch (e, stackTrace) {
      FosHuaweiLog.e('syncWorkouts failed', error: e, op: 'sync');
      
      // Capture full exception to Sentry for debugging
      if (SentryConfig.shouldInitialize) {
        await Sentry.captureException(
          e,
          stackTrace: stackTrace,
          hint: Hint.withMap({
            'mechanism': 'platform_exception',
            'context': 'workout_sync',
            'error_code': e.code,
            'error_message': e.message,
            'error_details': e.details?.toString(),
          }),
        );
      }
      
      await SentrySyncInstrumentation.finishWithStatus(
        span,
        status: 'error',
      );
      return WorkoutSyncResult(
        status: WorkoutSyncStatus.error,
        // Safe short reason only — never forward raw protocol/hex details.
        message: e.message ?? e.code,
        workouts: const [],
      );
    } finally {
      _syncInFlight = false;
    }
  }

  /// Activity Sync (sleep + FitnessTotals + TruSleep FileDownload).
  /// Shares single-flight with workouts. Does not pull continuous / daily HR.
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
    final spanDays = ((end - start) / 86400).ceil().clamp(1, activityWindowDays);
    FosHuaweiLog.i(
      'syncActivity window=[$start,$end] (~${spanDays}d class=$window)',
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
    } on PlatformException catch (e, stackTrace) {
      FosHuaweiLog.e('syncActivity failed', error: e, op: 'sync');
      
      // Capture full exception to Sentry for debugging
      if (SentryConfig.shouldInitialize) {
        await Sentry.captureException(
          e,
          stackTrace: stackTrace,
          hint: Hint.withMap({
            'mechanism': 'platform_exception',
            'context': 'activity_sync',
            'error_code': e.code,
            'error_message': e.message,
            'error_details': e.details?.toString(),
          }),
        );
      }
      
      await SentrySyncInstrumentation.finishWithStatus(
        span,
        status: 'error',
      );
      return ActivitySyncResult(
        status: ActivitySyncStatus.error,
        message: e.message ?? e.code,
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

  /// Debug-only physio capture probe (dict / sleep_data / optional path-2).
  /// Privacy-safe map only — never merges into TruSleep SoT.
  Future<Map<String, dynamic>> probePhysioCapture({
    bool includeDict = true,
    bool includeSleepData = true,
    bool includePath2Intervals = false,
    int? startUnix,
    int? endUnix,
  }) async {
    assert(kDebugMode, 'probePhysioCapture is debug-only');
    if (_syncInFlight) {
      return {
        'status': 'busy',
        'message': 'Another Sync is already in progress',
        'feedsProductSleepSot': false,
      };
    }
    if (!sessionReady) {
      return {
        'status': 'not_ready',
        'message': 'Connect and authenticate first',
        'feedsProductSleepSot': false,
      };
    }
    _syncInFlight = true;
    FosHuaweiLog.i(
      'probePhysioCapture start dict=$includeDict sleepData=$includeSleepData '
      'path2=$includePath2Intervals window=[$startUnix,$endUnix]',
      op: 'physio-probe',
    );
    try {
      return await _channel.probePhysioCapture(
        includeDict: includeDict,
        includeSleepData: includeSleepData,
        includePath2Intervals: includePath2Intervals,
        startUnix: startUnix,
        endUnix: endUnix,
      );
    } on PlatformException catch (e) {
      FosHuaweiLog.e('probePhysioCapture failed', error: e, op: 'physio-probe');
      return {
        'status': 'error',
        'message': e.message ?? 'probe failed',
        'feedsProductSleepSot': false,
      };
    } finally {
      _syncInFlight = false;
    }
  }

  /// Debug-only: download + persist `sleep_data.bin` for offline decode.
  /// Never merges into TruSleep SoT.
  Future<Map<String, dynamic>> persistSleepDataCapture({
    int? startUnix,
    int? endUnix,
  }) async {
    assert(kDebugMode, 'persistSleepDataCapture is debug-only');
    if (_syncInFlight) {
      return {
        'status': 'busy',
        'message': 'Another Sync is already in progress',
        'feedsProductSleepSot': false,
        'persisted': false,
      };
    }
    if (!sessionReady) {
      return {
        'status': 'not_ready',
        'message': 'Connect and authenticate first',
        'feedsProductSleepSot': false,
        'persisted': false,
      };
    }
    _syncInFlight = true;
    FosHuaweiLog.i(
      'persistSleepDataCapture start window=[$startUnix,$endUnix]',
      op: 'sleep-data-persist',
    );
    try {
      return await _channel.persistSleepDataCapture(
        startUnix: startUnix,
        endUnix: endUnix,
      );
    } on PlatformException catch (e) {
      FosHuaweiLog.e(
        'persistSleepDataCapture failed',
        error: e,
        op: 'sleep-data-persist',
      );
      return {
        'status': 'error',
        'message': e.message ?? 'persist failed',
        'feedsProductSleepSot': false,
        'persisted': false,
      };
    } finally {
      _syncInFlight = false;
    }
  }

  /// Debug-only: download + persist SEQUENCE_DATA SLEEP_DETAILS for offline decode.
  /// Never merges into TruSleep SoT.
  Future<Map<String, dynamic>> persistSleepDetailsSequenceCapture({
    int? startUnix,
    int? endUnix,
  }) async {
    assert(kDebugMode, 'persistSleepDetailsSequenceCapture is debug-only');
    if (_syncInFlight) {
      return {
        'status': 'busy',
        'message': 'Another Sync is already in progress',
        'feedsProductSleepSot': false,
        'persisted': false,
      };
    }
    if (!sessionReady) {
      return {
        'status': 'not_ready',
        'message': 'Connect and authenticate first',
        'feedsProductSleepSot': false,
        'persisted': false,
      };
    }
    _syncInFlight = true;
    FosHuaweiLog.i(
      'persistSleepDetailsSequenceCapture start window=[$startUnix,$endUnix]',
      op: 'sleep-dict-persist',
    );
    try {
      return await _channel.persistSleepDetailsSequenceCapture(
        startUnix: startUnix,
        endUnix: endUnix,
      );
    } on MissingPluginException catch (e) {
      FosHuaweiLog.e(
        'persistSleepDetailsSequenceCapture missing plugin — full rebuild required',
        error: e,
        op: 'sleep-dict-persist',
      );
      return {
        'status': 'error',
        'message':
            'Native method missing — stop app and full rebuild (hot restart is not enough)',
        'feedsProductSleepSot': false,
        'persisted': false,
      };
    } on PlatformException catch (e) {
      FosHuaweiLog.e(
        'persistSleepDetailsSequenceCapture failed',
        error: e,
        op: 'sleep-dict-persist',
      );
      return {
        'status': 'error',
        'message': e.message ?? 'persist failed',
        'feedsProductSleepSot': false,
        'persisted': false,
      };
    } finally {
      _syncInFlight = false;
    }
  }

  /// Wait while the link is mid-handshake. Fail fast on terminal / idle states.
  Future<bool> _awaitSessionReady({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (sessionReady) return true;
    // Use [state] (not [_state]) so test doubles that override the getter work.
    final current = state;
    if (current != LinkState.connecting &&
        current != LinkState.authenticating) {
      return false;
    }
    FosHuaweiLog.i(
      'syncWorkouts waiting for sessionReady (state=$current)',
      op: 'sync',
    );
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (sessionReady) {
        FosHuaweiLog.i(
          'syncWorkouts sessionReady after wait (state=$state)',
          op: 'sync',
        );
        return true;
      }
      final s = state;
      if (s != LinkState.connecting && s != LinkState.authenticating) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return sessionReady;
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

class SleepFileRef {
  const SleepFileRef({required this.id, required this.len, this.path});

  /// Filename id (`sleep_state` / `sleep_data`) — length only, never payload.
  final String id;
  final int len;

  /// App-private relative path when native persisted the blob.
  final String? path;

  factory SleepFileRef.fromMap(Map<String, dynamic> map) {
    int asInt(Object? v) => v == null ? 0 : (v as num).toInt();
    final path = map['path']?.toString();
    return SleepFileRef(
      id: map['id']?.toString() ?? '',
      len: asInt(map['len']),
      path: (path == null || path.isEmpty) ? null : path,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'len': len,
        if (path != null) 'path': path,
      };
}

/// Privacy-safe watch zone/clock from native activity Sync (Sentry observe).
class WatchClockSnapshot {
  const WatchClockSnapshot({
    required this.zoneId,
    required this.offsetSec,
    required this.offsetLabel,
    this.skewSec,
    this.phoneUnix,
    this.deviceUnix,
  });

  final String zoneId;
  final int offsetSec;
  final String offsetLabel;
  final int? skewSec;
  final int? phoneUnix;
  final int? deviceUnix;

  factory WatchClockSnapshot.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    return WatchClockSnapshot(
      zoneId: map['zoneId'] as String? ?? '',
      offsetSec: asInt(map['offsetSec']) ?? 0,
      offsetLabel: map['offsetLabel'] as String? ?? '',
      skewSec: asInt(map['skewSec']),
      phoneUnix: asInt(map['phoneUnix']),
      deviceUnix: asInt(map['deviceUnix']),
    );
  }
}

class SleepStateInterval {
  const SleepStateInterval({required this.beginUnix, required this.endUnix});

  final int beginUnix;
  final int endUnix;

  factory SleepStateInterval.fromMap(Map<String, dynamic> map) {
    int asInt(Object? v) => v == null ? 0 : (v as num).toInt();
    return SleepStateInterval(
      beginUnix: asInt(map['beginUnix']),
      endUnix: asInt(map['endUnix']),
    );
  }

  Map<String, dynamic> toJson() => {
        'beginUnix': beginUnix,
        'endUnix': endUnix,
      };
}

class SleepEnrichOutcome {
  const SleepEnrichOutcome({
    required this.beginUnix,
    required this.endUnix,
    required this.present,
    this.wireType,
    this.refs = const [],
    this.stateIntervals = const [],
    this.sequenceSessions = const [],
  });

  final int beginUnix;
  final int endUnix;
  final int? wireType;
  final bool present;
  final List<SleepFileRef> refs;
  final List<SleepStateInterval> stateIntervals;

  /// Parsed SEQUENCE_DATA SLEEP_DETAILS sessions (structured; no bodies).
  final List<TruSleepSequenceSession> sequenceSessions;

  SleepSessionSummary get asSession => SleepSessionSummary(
        beginUnix: beginUnix,
        endUnix: endUnix,
        wireType: wireType,
      );

  factory SleepEnrichOutcome.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    final refs = <SleepFileRef>[];
    final rawRefs = map['refs'];
    if (rawRefs is List) {
      for (final item in rawRefs) {
        if (item is Map) {
          final ref = SleepFileRef.fromMap(Map<String, dynamic>.from(item));
          if (ref.id.isNotEmpty) refs.add(ref);
        }
      }
    }
    final intervals = <SleepStateInterval>[];
    final rawIntervals = map['stateIntervals'];
    if (rawIntervals is List) {
      for (final item in rawIntervals) {
        if (item is Map) {
          final iv =
              SleepStateInterval.fromMap(Map<String, dynamic>.from(item));
          if (iv.beginUnix > 0 && iv.endUnix > iv.beginUnix) {
            intervals.add(iv);
          }
        }
      }
    }
    final sequence = <TruSleepSequenceSession>[];
    final rawSeq = map['sequenceSessions'];
    if (rawSeq is List) {
      for (final item in rawSeq) {
        if (item is Map) {
          final s =
              TruSleepSequenceSession.fromMap(Map<String, dynamic>.from(item));
          if (s.beginUnix > 0 && s.endUnix > s.beginUnix) {
            sequence.add(s);
          }
        }
      }
    }
    return SleepEnrichOutcome(
      beginUnix: asInt(map['beginUnix']) ?? 0,
      endUnix: asInt(map['endUnix']) ?? 0,
      wireType: asInt(map['wireType']),
      present: map['present'] == true,
      refs: refs,
      stateIntervals: intervals,
      sequenceSessions: sequence,
    );
  }
}

/// One TruSleep SEQUENCE_DATA session (summary scalars + product stages).
class TruSleepSequenceSession {
  const TruSleepSequenceSession({
    required this.beginUnix,
    required this.endUnix,
    this.sleepScore,
    this.avgHrv,
    this.avgHeartRate,
    this.avgBreathRate,
    this.avgOxygenSaturation,
    this.sleepEfficiency,
    this.sleepLatencySec,
    this.deepPart,
    this.bedTimeUnix,
    this.fallAsleepUnix,
    this.wakeupUnix,
    this.risingUnix,
    this.minHeartRate,
    this.maxHeartRate,
    this.productStages = const [],
  });

  final int beginUnix;
  final int endUnix;
  final int? sleepScore;
  final int? avgHrv;
  final int? avgHeartRate;
  final int? avgBreathRate;
  final int? avgOxygenSaturation;
  final int? sleepEfficiency;
  final int? sleepLatencySec;
  final int? deepPart;
  final int? bedTimeUnix;
  final int? fallAsleepUnix;
  final int? wakeupUnix;
  final int? risingUnix;
  final int? minHeartRate;
  final int? maxHeartRate;
  final List<SleepStageSummary> productStages;

  /// TruSleep scientific overnight (naps / stubs use score 0 + sentinels).
  bool get isScientific => (sleepScore ?? 0) > 0;

  /// Efficiency is 0–100; nap stubs often emit 255.
  int? get usableEfficiency {
    final v = sleepEfficiency;
    if (v == null || v < 0 || v > 100) return null;
    return v;
  }

  /// Deep-sleep continuity score (Health Kit deep_sleep_part), not deep minutes.
  int? get usableDeepPart {
    final v = deepPart;
    if (v == null || v < 0 || v > 100) return null;
    return v;
  }

  /// Latency bed→sleep; reject absurd nap sentinels.
  int? get usableLatencySec {
    final v = sleepLatencySec;
    if (v == null || v < 0 || v > 3 * 3600) return null;
    return v;
  }

  factory TruSleepSequenceSession.fromMap(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    final stages = <SleepStageSummary>[];
    // Prefer remapped productStages (message-path wireType); ignore raw SEQUENCE codes.
    final raw = map['productStages'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final st = SleepStageSummary.fromMap(Map<String, dynamic>.from(item));
        if (st.timestampUnix > 0 && st.durationMin > 0) stages.add(st);
      }
    }
    return TruSleepSequenceSession(
      beginUnix: asInt(map['beginUnix']) ?? 0,
      endUnix: asInt(map['endUnix']) ?? 0,
      sleepScore: asInt(map['sleepScore']),
      avgHrv: asInt(map['avgHrv']),
      avgHeartRate: asInt(map['avgHeartRate']),
      avgBreathRate: asInt(map['avgBreathRate']),
      avgOxygenSaturation: asInt(map['avgOxygenSaturation']),
      sleepEfficiency: asInt(map['sleepEfficiency']),
      sleepLatencySec: asInt(map['sleepLatencySec']),
      deepPart: asInt(map['deepPart']),
      bedTimeUnix: asInt(map['bedTimeUnix']),
      fallAsleepUnix: asInt(map['fallAsleepUnix']),
      wakeupUnix: asInt(map['wakeupUnix']),
      risingUnix: asInt(map['risingUnix']),
      minHeartRate: asInt(map['minHeartRate']),
      maxHeartRate: asInt(map['maxHeartRate']),
      productStages: stages,
    );
  }

  Map<String, dynamic> toSummaryJson() => {
        'beginUnix': beginUnix,
        'endUnix': endUnix,
        if (sleepScore != null) 'sleepScore': sleepScore,
        if (avgHrv != null) 'avgHrv': avgHrv,
        if (avgHeartRate != null) 'avgHeartRate': avgHeartRate,
        if (avgBreathRate != null) 'avgBreathRate': avgBreathRate,
        if (avgOxygenSaturation != null)
          'avgOxygenSaturation': avgOxygenSaturation,
        if (sleepEfficiency != null) 'sleepEfficiency': sleepEfficiency,
        if (sleepLatencySec != null) 'sleepLatencySec': sleepLatencySec,
        if (deepPart != null) 'deepPart': deepPart,
        if (bedTimeUnix != null) 'bedTimeUnix': bedTimeUnix,
        if (fallAsleepUnix != null) 'fallAsleepUnix': fallAsleepUnix,
        if (wakeupUnix != null) 'wakeupUnix': wakeupUnix,
        if (risingUnix != null) 'risingUnix': risingUnix,
        if (minHeartRate != null) 'minHeartRate': minHeartRate,
        if (maxHeartRate != null) 'maxHeartRate': maxHeartRate,
        'source': 'sequence_data',
      };
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
    this.sleepEnrich = const [],
    this.watchClock,
  });

  final ActivitySyncStatus status;
  final String? message;
  final List<SleepSessionSummary> sleepSessions;
  final List<DailyHrSample> dailyHrSamples;
  final List<FitnessTotalsDay> fitnessTotals;
  final Set<String> completedContainers;
  final bool enableSkipped;

  /// TruSleep FileDownload outcomes (present only). Empty when absent/skipped.
  final List<SleepEnrichOutcome> sleepEnrich;

  /// Privacy-safe watch zone/clock from native (for Sentry observe).
  final WatchClockSnapshot? watchClock;

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
    final enrich = <SleepEnrichOutcome>[];
    final rawEnrich = map['sleepEnrich'];
    if (rawEnrich is List) {
      for (final item in rawEnrich) {
        if (item is Map) {
          enrich.add(
            SleepEnrichOutcome.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    WatchClockSnapshot? watchClock;
    final rawClock = map['watchClock'];
    if (rawClock is Map) {
      final snap =
          WatchClockSnapshot.fromMap(Map<String, dynamic>.from(rawClock));
      if (snap.zoneId.isNotEmpty) watchClock = snap;
    }
    return ActivitySyncResult(
      status: status,
      message: map['message'] as String?,
      sleepSessions: sleep,
      dailyHrSamples: hr,
      fitnessTotals: totals,
      completedContainers: completed,
      enableSkipped: map['enableSkipped'] as bool? ?? false,
      sleepEnrich: enrich,
      watchClock: watchClock,
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

/// Opaque Totals / sample / pace TLV body from native U1 channel maps.
///
/// Channel keys (per entry): `id`, `len`, `bodyBase64`.
/// Workout-level list key: `leftoverBodies`. Same key on `dataPages` /
/// `paceBlocks` entries when sample/pace bodies were captured.
/// U2 peels these into side-files before lean [WorkoutSummary] prefs write.
/// Never log or send to Sentry — length/id only outside the device.
class LeftoverTlvBody {
  const LeftoverTlvBody({
    required this.id,
    required this.len,
    required this.bodyBase64,
  });

  final int id;
  final int len;
  final String bodyBase64;

  factory LeftoverTlvBody.fromMap(Map<String, dynamic> map) {
    int asInt(Object? v) => v == null ? 0 : (v as num).toInt();
    return LeftoverTlvBody(
      id: asInt(map['id']),
      len: asInt(map['len']),
      bodyBase64: map['bodyBase64'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'len': len,
        'bodyBase64': bodyBase64,
      };
}

/// Honesty stamps for leftover / sample / pace streams (prefs refs only).
///
/// Never stamp [present] unless channel refs and side-files agree after write.
abstract final class WorkoutStreamHonesty {
  static const present = 'present';
  static const unobserved = 'unobserved';
  static const partial = 'partial';
  static const blocked = 'blocked';
  static const incomplete = 'incomplete';
}

/// Sample or pace page bodies peeled from a channel map entry.
///
/// Pace channel summaries may also carry [distanceM] / [paceSec] without
/// leftover bodies — those scalars survive into [RunSessionStore] meta for
/// the splits table (U4). Opaque [bodies] alone never invent chart points.
class PeeledPageBodies {
  const PeeledPageBodies({
    required this.index,
    required this.bodies,
    this.distanceM,
    this.paceSec,
  });

  final int index;
  final List<LeftoverTlvBody> bodies;

  /// Pace-block distance (metres) when native summary decoded it.
  final int? distanceM;

  /// Pace-block pace (seconds) when native summary decoded it.
  final int? paceSec;

  bool get hasPersistableContent =>
      bodies.isNotEmpty || distanceM != null || paceSec != null;
}

/// Bodies + honesty peeled from one native workout map before lean prefs write.
class PeeledWorkoutPayload {
  const PeeledWorkoutPayload({
    required this.workoutNumber,
    required this.totalsLeftovers,
    required this.dataPages,
    required this.paceBlocks,
    required this.leftoversStatus,
    required this.dataPagesStatus,
    required this.paceBlocksStatus,
    this.observedType,
  });

  final int workoutNumber;
  final List<LeftoverTlvBody> totalsLeftovers;
  final List<PeeledPageBodies> dataPages;
  final List<PeeledPageBodies> paceBlocks;
  final String leftoversStatus;
  final String dataPagesStatus;
  final String paceBlocksStatus;
  final int? observedType;

  bool get hasBodiesToPersist =>
      totalsLeftovers.isNotEmpty ||
      dataPages.any((p) => p.hasPersistableContent) ||
      paceBlocks.any((p) => p.hasPersistableContent);

  PeeledWorkoutPayload copyWith({
    String? leftoversStatus,
    String? dataPagesStatus,
    String? paceBlocksStatus,
  }) {
    return PeeledWorkoutPayload(
      workoutNumber: workoutNumber,
      totalsLeftovers: totalsLeftovers,
      dataPages: dataPages,
      paceBlocks: paceBlocks,
      leftoversStatus: leftoversStatus ?? this.leftoversStatus,
      dataPagesStatus: dataPagesStatus ?? this.dataPagesStatus,
      paceBlocksStatus: paceBlocksStatus ?? this.paceBlocksStatus,
      observedType: observedType,
    );
  }
}

/// Helpers for U1 channel maps retained on [WorkoutSyncResult.rawWorkouts].
///
/// New / retained raw keys (U2 peel surface):
/// - `leftoverBodies` — `List<{id, len, bodyBase64}>` on Totals workout maps
/// - `observedType` — wire type from Totals TLV `0x14` when present (no enum claim)
/// - `dataPages[]` / `paceBlocks[]` — may include nested `leftoverBodies` with
///   sample/pace opaque bodies (not summary-only)
/// Path-ref spill (`leftoverPath`) remains a U2 option if Binder size bites.
abstract final class WorkoutChannelRawKeys {
  static const leftoverBodies = 'leftoverBodies';
  static const bodyBase64 = 'bodyBase64';
  static const observedType = 'observedType';
  static const dataPages = 'dataPages';
  static const paceBlocks = 'paceBlocks';

  static List<LeftoverTlvBody> parseLeftoverBodies(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LeftoverTlvBody.fromMap(Map<String, dynamic>.from(e)))
        .where((b) => b.bodyBase64.isNotEmpty)
        .toList();
  }
}

/// Peel leftover / sample / pace bodies from a native workout map.
///
/// Called from [WorkoutSyncResult.fromMap] (HuaweiLink sync path) before lean
/// [WorkoutSummary] construction. Never logs body payloads — id/len only.
abstract final class WorkoutChannelPeel {
  static PeeledWorkoutPayload peel(Map<String, dynamic> raw) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    final number = asInt(raw['number']) ?? 0;
    final dataCount = asInt(raw['dataCount']) ?? 0;
    final paceCount = asInt(raw['paceCount']) ?? 0;
    final observedType = asInt(raw[WorkoutChannelRawKeys.observedType]);

    final leftovers = WorkoutChannelRawKeys.parseLeftoverBodies(
      raw[WorkoutChannelRawKeys.leftoverBodies],
    );
    final dataPages = _parsePagedBodies(raw[WorkoutChannelRawKeys.dataPages]);
    final paceBlocks = _parsePagedBodies(raw[WorkoutChannelRawKeys.paceBlocks]);

    return PeeledWorkoutPayload(
      workoutNumber: number,
      totalsLeftovers: leftovers,
      dataPages: dataPages,
      paceBlocks: paceBlocks,
      leftoversStatus: leftovers.isEmpty
          ? WorkoutStreamHonesty.unobserved
          : WorkoutStreamHonesty.present,
      dataPagesStatus: _streamStatus(
        countHint: dataCount,
        arrivedPages: dataPages.length,
      ),
      paceBlocksStatus: _streamStatus(
        countHint: paceCount,
        arrivedPages: paceBlocks.length,
      ),
      observedType: observedType,
    );
  }

  /// Lean summary for prefs: scalars + refs/stamps; never bodies/series.
  static WorkoutSummary leanSummary(
    Map<String, dynamic> raw,
    PeeledWorkoutPayload peeled,
  ) {
    final base = WorkoutSummary.fromMap(raw);
    return base.copyWith(
      observedType: peeled.observedType ?? base.observedType,
      leftoversStatus: peeled.leftoversStatus,
      dataPagesStatus: peeled.dataPagesStatus,
      paceBlocksStatus: peeled.paceBlocksStatus,
      leftoverRefs: peeled.totalsLeftovers
          .map((b) => EnrichmentTagRef(id: b.id, len: b.len))
          .toList(),
      dataPagesStored:
          peeled.dataPages.isEmpty ? null : peeled.dataPages.length,
      paceBlocksStored:
          peeled.paceBlocks.isEmpty ? null : peeled.paceBlocks.length,
    );
  }

  static String _streamStatus({
    required int countHint,
    required int arrivedPages,
  }) {
    if (countHint <= 0) return WorkoutStreamHonesty.unobserved;
    // Count promised pages but none arrived — partial/incomplete, not
    // Count=0 unobserved (ok parse-fail or soft-incomplete before first page).
    if (arrivedPages <= 0) return WorkoutStreamHonesty.partial;
    if (arrivedPages < countHint) return WorkoutStreamHonesty.partial;
    return WorkoutStreamHonesty.present;
  }

  static List<PeeledPageBodies> _parsePagedBodies(Object? raw) {
    if (raw is! List) return const [];
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    final out = <PeeledPageBodies>[];
    for (final item in raw.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item);
      final bodies = WorkoutChannelRawKeys.parseLeftoverBodies(
        map[WorkoutChannelRawKeys.leftoverBodies],
      );
      final index = asInt(map['index']) ?? 0;
      final distanceM = asInt(map['distanceM']);
      final paceSec = asInt(map['paceSec']);
      final page = PeeledPageBodies(
        index: index,
        bodies: bodies,
        distanceM: distanceM,
        paceSec: paceSec,
      );
      // Keep scalar-only pace summaries (distance/pace) even when no opaque
      // leftover bodies — required for the U4 splits table.
      if (!page.hasPersistableContent) continue;
      out.add(page);
    }
    return out;
  }
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
    this.load,
    this.aerobicEffect,
    this.anaerobicEffect,
    this.recoveryTime,
    this.trainingPoints,
    this.leftoverLen,
    this.leftoverPresent,
    this.leftoverPath,
    this.leftoverBytes,
    this.samplePath,
    this.sampleFetch,
    this.enrichmentTags,
    this.segments,
    this.observedType,
    this.leftoversStatus,
    this.dataPagesStatus,
    this.paceBlocksStatus,
    this.leftoverRefs,
    this.dataPagesStored,
    this.paceBlocksStored,
    this.parserGeneration,
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

  /// Locked Totals scalars — omit when absent (null ≠ 0).
  final int? load;
  final int? aerobicEffect;
  final int? anaerobicEffect;
  final int? recoveryTime;
  final int? trainingPoints;

  /// Lean leftover index: length + present + relative path. Never bodies in prefs.
  final int? leftoverLen;
  final bool? leftoverPresent;
  final String? leftoverPath;

  /// Channel-only Totals leftover body. Cleared before prefs write; never in [toJson].
  final Uint8List? leftoverBytes;

  /// Relative path under [GateAPrefs.workoutHrSamplesDir] when native wrote points.
  final String? samplePath;

  /// Sample-page fetch honesty: `none` | `ok` | `partial` | `timeout`.
  final String? sampleFetch;

  final List<EnrichmentTagRef>? enrichmentTags;
  final List<WorkoutSegment>? segments;

  /// Wire type from Totals TLV `0x14` when present (prove-session freeze input).
  final int? observedType;

  /// Honesty for Totals leftover side-files ([WorkoutStreamHonesty]).
  final String? leftoversStatus;

  /// Honesty for WorkoutData sample page side-files.
  final String? dataPagesStatus;

  /// Honesty for Pace block side-files.
  final String? paceBlocksStatus;

  /// Prefs-only leftover refs (id+len). Bodies live in [RunSessionStore].
  final List<EnrichmentTagRef>? leftoverRefs;

  /// Count of sample pages persisted to side-files (not an invented series).
  final int? dataPagesStored;

  /// Count of pace blocks persisted to side-files.
  final int? paceBlocksStored;

  /// Parser generation that wrote leftovers/scalars (monotonic escape hatch).
  final int? parserGeneration;

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
    List<EnrichmentTagRef>? leftoverRefs;
    final rawLeftoverRefs = map['leftoverRefs'];
    if (rawLeftoverRefs is List) {
      leftoverRefs = rawLeftoverRefs
          .whereType<Map>()
          .map((e) => EnrichmentTagRef.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    // Channel may deliver leftover as Uint8List; prefs must never re-embed it.
    Uint8List? leftoverBytes;
    final rawLeftover = map['leftover'];
    if (rawLeftover is Uint8List) {
      leftoverBytes = rawLeftover;
    } else if (rawLeftover is List) {
      leftoverBytes = Uint8List.fromList(
        rawLeftover.map((e) => (e as num).toInt()).toList(),
      );
    }
    final leftoverLen =
        asInt(map['leftoverLen']) ?? leftoverBytes?.length;
    final leftoverPresent = map['leftoverPresent'] as bool? ??
        (leftoverBytes != null && leftoverBytes.isNotEmpty
            ? true
            : (map['leftoverPath'] != null ? true : null));
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
      load: asInt(map['load']),
      aerobicEffect: asInt(map['aerobicEffect']),
      anaerobicEffect: asInt(map['anaerobicEffect']),
      recoveryTime: asInt(map['recoveryTime']),
      trainingPoints: asInt(map['trainingPoints']),
      leftoverLen: leftoverLen,
      leftoverPresent: leftoverPresent,
      leftoverPath: _relativeWorkoutPath(
        map['leftoverPath']?.toString(),
        expectedDir: 'workouts/leftovers',
      ),
      leftoverBytes: leftoverBytes,
      samplePath: _relativeWorkoutPath(
        map['samplePath']?.toString(),
        expectedDir: 'workouts/hr_samples',
      ),
      sampleFetch: map['sampleFetch'] as String?,
      enrichmentTags: tags,
      segments: segments,
      observedType: asInt(map['observedType']),
      leftoversStatus: map['leftoversStatus'] as String?,
      dataPagesStatus: map['dataPagesStatus'] as String?,
      paceBlocksStatus: map['paceBlocksStatus'] as String?,
      leftoverRefs: leftoverRefs,
      dataPagesStored: asInt(map['dataPagesStored']),
      paceBlocksStored: asInt(map['paceBlocksStored']),
      parserGeneration: asInt(map['parserGeneration']),
    );
  }

  /// Lean prefs / Coach Settings index — never leftover bodies or HR series.
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
        if (load != null) 'load': load,
        if (aerobicEffect != null) 'aerobicEffect': aerobicEffect,
        if (anaerobicEffect != null) 'anaerobicEffect': anaerobicEffect,
        if (recoveryTime != null) 'recoveryTime': recoveryTime,
        if (trainingPoints != null) 'trainingPoints': trainingPoints,
        if (leftoverLen != null) 'leftoverLen': leftoverLen,
        if (leftoverPresent != null) 'leftoverPresent': leftoverPresent,
        if (leftoverPath != null) 'leftoverPath': leftoverPath,
        if (samplePath != null) 'samplePath': samplePath,
        if (sampleFetch != null) 'sampleFetch': sampleFetch,
        if (enrichmentTags != null && enrichmentTags!.isNotEmpty)
          'enrichmentTags': enrichmentTags!.map((t) => t.toJson()).toList(),
        if (segments != null && segments!.isNotEmpty)
          'segments': segments!.map((s) => s.toJson()).toList(),
        if (observedType != null) 'observedType': observedType,
        if (leftoversStatus != null) 'leftoversStatus': leftoversStatus,
        if (dataPagesStatus != null) 'dataPagesStatus': dataPagesStatus,
        if (paceBlocksStatus != null) 'paceBlocksStatus': paceBlocksStatus,
        if (leftoverRefs != null && leftoverRefs!.isNotEmpty)
          'leftoverRefs': leftoverRefs!.map((t) => t.toJson()).toList(),
        if (dataPagesStored != null) 'dataPagesStored': dataPagesStored,
        if (paceBlocksStored != null) 'paceBlocksStored': paceBlocksStored,
        if (parserGeneration != null) 'parserGeneration': parserGeneration,
      };

  WorkoutSummary copyWith({
    int? number,
    int? startTime,
    int? endTime,
    int? durationSec,
    int? type,
    int? calories,
    int? distanceM,
    int? steps,
    int? dataCount,
    int? paceCount,
    int? segmentsCount,
    int? sampleCount,
    String? enrichmentStatus,
    int? hrMin,
    int? hrMax,
    int? hrPeak,
    int? swimType,
    int? strokes,
    int? strokeRate,
    int? avgSwolf,
    String? sessionFlag,
    int? poolLength,
    int? laps,
    int? load,
    int? aerobicEffect,
    int? anaerobicEffect,
    int? recoveryTime,
    int? trainingPoints,
    int? leftoverLen,
    bool? leftoverPresent,
    String? leftoverPath,
    Uint8List? leftoverBytes,
    bool clearLeftoverBytes = false,
    bool clearLeftoverPath = false,
    String? samplePath,
    String? sampleFetch,
    List<EnrichmentTagRef>? enrichmentTags,
    List<WorkoutSegment>? segments,
    int? observedType,
    String? leftoversStatus,
    String? dataPagesStatus,
    String? paceBlocksStatus,
    List<EnrichmentTagRef>? leftoverRefs,
    int? dataPagesStored,
    int? paceBlocksStored,
    int? parserGeneration,
  }) {
    return WorkoutSummary(
      number: number ?? this.number,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSec: durationSec ?? this.durationSec,
      type: type ?? this.type,
      calories: calories ?? this.calories,
      distanceM: distanceM ?? this.distanceM,
      steps: steps ?? this.steps,
      dataCount: dataCount ?? this.dataCount,
      paceCount: paceCount ?? this.paceCount,
      segmentsCount: segmentsCount ?? this.segmentsCount,
      sampleCount: sampleCount ?? this.sampleCount,
      enrichmentStatus: enrichmentStatus ?? this.enrichmentStatus,
      hrMin: hrMin ?? this.hrMin,
      hrMax: hrMax ?? this.hrMax,
      hrPeak: hrPeak ?? this.hrPeak,
      swimType: swimType ?? this.swimType,
      strokes: strokes ?? this.strokes,
      strokeRate: strokeRate ?? this.strokeRate,
      avgSwolf: avgSwolf ?? this.avgSwolf,
      sessionFlag: sessionFlag ?? this.sessionFlag,
      poolLength: poolLength ?? this.poolLength,
      laps: laps ?? this.laps,
      load: load ?? this.load,
      aerobicEffect: aerobicEffect ?? this.aerobicEffect,
      anaerobicEffect: anaerobicEffect ?? this.anaerobicEffect,
      recoveryTime: recoveryTime ?? this.recoveryTime,
      trainingPoints: trainingPoints ?? this.trainingPoints,
      leftoverLen: leftoverLen ?? this.leftoverLen,
      leftoverPresent: leftoverPresent ?? this.leftoverPresent,
      leftoverPath:
          clearLeftoverPath ? null : (leftoverPath ?? this.leftoverPath),
      leftoverBytes:
          clearLeftoverBytes ? null : (leftoverBytes ?? this.leftoverBytes),
      samplePath: samplePath ?? this.samplePath,
      sampleFetch: sampleFetch ?? this.sampleFetch,
      enrichmentTags: enrichmentTags ?? this.enrichmentTags,
      segments: segments ?? this.segments,
      observedType: observedType ?? this.observedType,
      leftoversStatus: leftoversStatus ?? this.leftoversStatus,
      dataPagesStatus: dataPagesStatus ?? this.dataPagesStatus,
      paceBlocksStatus: paceBlocksStatus ?? this.paceBlocksStatus,
      leftoverRefs: leftoverRefs ?? this.leftoverRefs,
      dataPagesStored: dataPagesStored ?? this.dataPagesStored,
      paceBlocksStored: paceBlocksStored ?? this.paceBlocksStored,
      parserGeneration: parserGeneration ?? this.parserGeneration,
    );
  }
}
/// Keep relative paths under a registered workouts side-file dir; drop absolutes.
String? _relativeWorkoutPath(String? raw, {required String expectedDir}) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final normalized = trimmed.replaceAll('\\', '/');
  final marker = '$expectedDir/';
  final idx = normalized.indexOf(marker);
  if (idx >= 0) {
    final rel = normalized.substring(idx);
    if (rel.contains('..')) return null;
    return rel;
  }
  // Bare filename from native — nest under the registered dir.
  if (!normalized.contains('/') && !normalized.startsWith('/')) {
    return '$marker$normalized';
  }
  return null;
}

class WorkoutSyncResult {
  const WorkoutSyncResult({
    required this.status,
    required this.workouts,
    this.message,
    this.rawWorkouts,
    this.peeled,
  });

  final WorkoutSyncStatus status;
  final List<WorkoutSummary> workouts;
  final String? message;

  /// Native workout maps before lean [WorkoutSummary] construction.
  ///
  /// Preserves U1 body-bearing keys (`leftoverBodies`, nested sample/pace
  /// bodies on `dataPages` / `paceBlocks`, `observedType`) for U2 peel/store.
  /// [WorkoutSummary.fromMap] still drops those keys by design.
  final List<Map<String, dynamic>>? rawWorkouts;

  /// Bodies peeled at [WorkoutSyncResult.fromMap] for [RunSessionStore] write.
  /// Parallel to [workouts]; never log — length/id only outside the device.
  final List<PeeledWorkoutPayload>? peeled;

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
    final rawWorkouts = <Map<String, dynamic>>[];
    final peeled = <PeeledWorkoutPayload>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          final raw = Map<String, dynamic>.from(item);
          rawWorkouts.add(raw);
          final peel = WorkoutChannelPeel.peel(raw);
          peeled.add(peel);
          workouts.add(WorkoutChannelPeel.leanSummary(raw, peel));
        }
      }
    }
    return WorkoutSyncResult(
      status: status,
      workouts: workouts,
      message: map['message'] as String?,
      rawWorkouts: rawWorkouts.isEmpty ? null : rawWorkouts,
      peeled: peeled.isEmpty ? null : peeled,
    );
  }
}

/// Enrichment-monotonic WorkoutSummary merge (workout-history-wide).
///
/// Prefer richer stream completeness; fill-null Totals scalars; retain denser
/// swim segments. Allow leftover/scalar replacement when [incoming]'s
/// parserGeneration (or [currentParserGeneration]) exceeds the existing row.
abstract final class WorkoutEnrichmentMerge {
  static WorkoutSummary mergeRow({
    required WorkoutSummary existing,
    required WorkoutSummary incoming,
    required int currentParserGeneration,
  }) {
    final existingGen = existing.parserGeneration ?? 0;
    final incomingGen =
        incoming.parserGeneration ?? currentParserGeneration;
    final allowReplace =
        incomingGen > existingGen || currentParserGeneration > existingGen;

    // Totals scalars: incoming non-null wins (watch Totals SoT); null keeps
    // existing. Parser bump uses the same rule (incoming may remap).
    T? totalsScalar<T>(T? existingV, T? incomingV) =>
        incomingV ?? existingV;

    final leftovers = _preferStream(
      existingStatus: existing.leftoversStatus,
      incomingStatus: incoming.leftoversStatus,
      existingRefs: existing.leftoverRefs,
      incomingRefs: incoming.leftoverRefs,
      existingStored: existing.leftoverRefs?.length,
      incomingStored: incoming.leftoverRefs?.length,
      allowReplace: allowReplace,
    );
    final dataPages = _preferStream(
      existingStatus: existing.dataPagesStatus,
      incomingStatus: incoming.dataPagesStatus,
      existingRefs: null,
      incomingRefs: null,
      existingStored: existing.dataPagesStored,
      incomingStored: incoming.dataPagesStored,
      allowReplace: allowReplace,
    );
    final paceBlocks = _preferStream(
      existingStatus: existing.paceBlocksStatus,
      incomingStatus: incoming.paceBlocksStatus,
      existingRefs: null,
      incomingRefs: null,
      existingStored: existing.paceBlocksStored,
      incomingStored: incoming.paceBlocksStored,
      allowReplace: allowReplace,
    );

    return WorkoutSummary(
      number: incoming.number != 0 ? incoming.number : existing.number,
      startTime:
          incoming.startTime != 0 ? incoming.startTime : existing.startTime,
      endTime: incoming.endTime != 0 ? incoming.endTime : existing.endTime,
      durationSec: incoming.durationSec != 0
          ? incoming.durationSec
          : existing.durationSec,
      type: incoming.type != 0 ? incoming.type : existing.type,
      calories: totalsScalar(existing.calories, incoming.calories),
      distanceM: totalsScalar(existing.distanceM, incoming.distanceM),
      steps: totalsScalar(existing.steps, incoming.steps),
      dataCount: totalsScalar(existing.dataCount, incoming.dataCount),
      paceCount: totalsScalar(existing.paceCount, incoming.paceCount),
      segmentsCount: totalsScalar(existing.segmentsCount, incoming.segmentsCount),
      sampleCount: totalsScalar(existing.sampleCount, incoming.sampleCount),
      enrichmentStatus: _preferEnrichmentStatus(
        existing.enrichmentStatus,
        incoming.enrichmentStatus,
      ),
      hrMin: totalsScalar(existing.hrMin, incoming.hrMin),
      hrMax: totalsScalar(existing.hrMax, incoming.hrMax),
      hrPeak: totalsScalar(existing.hrPeak, incoming.hrPeak),
      swimType: totalsScalar(existing.swimType, incoming.swimType),
      strokes: totalsScalar(existing.strokes, incoming.strokes),
      strokeRate: totalsScalar(existing.strokeRate, incoming.strokeRate),
      avgSwolf: totalsScalar(existing.avgSwolf, incoming.avgSwolf),
      sessionFlag: totalsScalar(existing.sessionFlag, incoming.sessionFlag),
      poolLength: totalsScalar(existing.poolLength, incoming.poolLength),
      laps: totalsScalar(existing.laps, incoming.laps),
      load: totalsScalar(existing.load, incoming.load),
      aerobicEffect:
          totalsScalar(existing.aerobicEffect, incoming.aerobicEffect),
      anaerobicEffect:
          totalsScalar(existing.anaerobicEffect, incoming.anaerobicEffect),
      recoveryTime:
          totalsScalar(existing.recoveryTime, incoming.recoveryTime),
      trainingPoints:
          totalsScalar(existing.trainingPoints, incoming.trainingPoints),
      leftoverLen: totalsScalar(existing.leftoverLen, incoming.leftoverLen),
      leftoverPresent:
          totalsScalar(existing.leftoverPresent, incoming.leftoverPresent),
      leftoverPath:
          totalsScalar(existing.leftoverPath, incoming.leftoverPath),
      leftoverBytes:
          totalsScalar(existing.leftoverBytes, incoming.leftoverBytes),
      samplePath: totalsScalar(existing.samplePath, incoming.samplePath),
      sampleFetch: totalsScalar(existing.sampleFetch, incoming.sampleFetch),
      enrichmentTags: _preferTagList(
        existing.enrichmentTags,
        incoming.enrichmentTags,
        allowReplace: allowReplace,
      ),
      segments: _preferSegments(
        existing.segments,
        incoming.segments,
        allowReplace: allowReplace,
      ),
      observedType: totalsScalar(existing.observedType, incoming.observedType),
      leftoversStatus: leftovers.status,
      dataPagesStatus: dataPages.status,
      paceBlocksStatus: paceBlocks.status,
      leftoverRefs: leftovers.refs ??
          (leftovers.preferIncoming
              ? incoming.leftoverRefs
              : existing.leftoverRefs),
      dataPagesStored: dataPages.stored,
      paceBlocksStored: paceBlocks.stored,
      parserGeneration: allowReplace
          ? (incomingGen > 0 ? incomingGen : currentParserGeneration)
          : (existingGen > 0
              ? existingGen
              : (incomingGen > 0 ? incomingGen : currentParserGeneration)),
    );
  }

  /// Session-level honesty: soft-incomplete or any stream partial/incomplete
  /// → `partial`; otherwise `ok` only when no stream claims present without
  /// agreeing refs (caller reconciles files before stamping).
  static String sessionEnrichmentStatus({
    required bool softIncomplete,
    required WorkoutSummary workout,
  }) {
    if (softIncomplete) return 'partial';
    if (_streamIncomplete(workout.leftoversStatus) ||
        _streamIncomplete(workout.dataPagesStatus) ||
        _streamIncomplete(workout.paceBlocksStatus)) {
      return 'partial';
    }
    return 'ok';
  }

  static bool _streamIncomplete(String? status) =>
      status == WorkoutStreamHonesty.partial ||
      status == WorkoutStreamHonesty.incomplete;

  static int streamRichness(String? status) {
    return switch (status) {
      WorkoutStreamHonesty.present => 4,
      WorkoutStreamHonesty.partial => 3,
      WorkoutStreamHonesty.incomplete => 2,
      WorkoutStreamHonesty.unobserved => 1,
      WorkoutStreamHonesty.blocked => 0,
      _ => 0,
    };
  }

  static String? _preferEnrichmentStatus(String? existing, String? incoming) {
    // Full ok Sync must clear sticky partial so cursor overlap can shrink and
    // UI honesty can leave "Sync: partial" (U3).
    if (incoming == 'ok') return 'ok';
    if (existing == 'partial' || incoming == 'partial') return 'partial';
    return incoming ?? existing;
  }

  static List<EnrichmentTagRef>? _preferTagList(
    List<EnrichmentTagRef>? existing,
    List<EnrichmentTagRef>? incoming, {
    required bool allowReplace,
  }) {
    if (allowReplace && incoming != null && incoming.isNotEmpty) {
      return incoming;
    }
    final eLen = existing?.length ?? 0;
    final iLen = incoming?.length ?? 0;
    if (iLen > eLen) return incoming;
    if (eLen > 0) return existing;
    return incoming;
  }

  static List<WorkoutSegment>? _preferSegments(
    List<WorkoutSegment>? existing,
    List<WorkoutSegment>? incoming, {
    required bool allowReplace,
  }) {
    if (allowReplace && incoming != null && incoming.isNotEmpty) {
      return incoming;
    }
    final eScore = _segmentRichness(existing);
    final iScore = _segmentRichness(incoming);
    if (iScore > eScore) return incoming;
    if (eScore > 0) return existing;
    return incoming;
  }

  static int _segmentRichness(List<WorkoutSegment>? segments) {
    if (segments == null || segments.isEmpty) return 0;
    var score = segments.length * 10;
    for (final s in segments) {
      if (s.style != null) score += 3;
      if (s.strokes != null) score += 2;
      if (s.distanceM != null) score += 1;
      if (s.durationSec != null) score += 1;
    }
    return score;
  }

  static _StreamPick _preferStream({
    required String? existingStatus,
    required String? incomingStatus,
    required List<EnrichmentTagRef>? existingRefs,
    required List<EnrichmentTagRef>? incomingRefs,
    required int? existingStored,
    required int? incomingStored,
    required bool allowReplace,
  }) {
    if (allowReplace &&
        streamRichness(incomingStatus) >= streamRichness(existingStatus) &&
        (incomingStatus != null ||
            (incomingStored ?? 0) > 0 ||
            (incomingRefs?.isNotEmpty ?? false))) {
      return _StreamPick(
        status: incomingStatus ?? existingStatus,
        refs: incomingRefs ?? existingRefs,
        stored: incomingStored ?? existingStored,
        preferIncoming: true,
      );
    }
    final eR = streamRichness(existingStatus);
    final iR = streamRichness(incomingStatus);
    if (iR > eR) {
      return _StreamPick(
        status: incomingStatus,
        refs: incomingRefs ?? existingRefs,
        stored: incomingStored ?? existingStored,
        preferIncoming: true,
      );
    }
    if (eR > iR) {
      return _StreamPick(
        status: existingStatus,
        refs: existingRefs ?? incomingRefs,
        stored: existingStored ?? incomingStored,
        preferIncoming: false,
      );
    }
    // Tie on status — prefer denser stored count / refs.
    final eStore = existingStored ?? existingRefs?.length ?? 0;
    final iStore = incomingStored ?? incomingRefs?.length ?? 0;
    if (iStore > eStore) {
      return _StreamPick(
        status: incomingStatus ?? existingStatus,
        refs: incomingRefs ?? existingRefs,
        stored: incomingStored ?? existingStored,
        preferIncoming: true,
      );
    }
    return _StreamPick(
      status: existingStatus ?? incomingStatus,
      refs: existingRefs ?? incomingRefs,
      stored: existingStored ?? incomingStored,
      preferIncoming: false,
    );
  }
}

class _StreamPick {
  const _StreamPick({
    required this.status,
    required this.refs,
    required this.stored,
    required this.preferIncoming,
  });

  final String? status;
  final List<EnrichmentTagRef>? refs;
  final int? stored;
  final bool preferIncoming;
}

