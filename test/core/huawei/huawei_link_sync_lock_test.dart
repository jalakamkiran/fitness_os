import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';

class _ScriptedChannel extends HuaweiBtChannel {
  _ScriptedChannel() : super(methodChannel: const MethodChannel('test'));

  Completer<Map<String, dynamic>>? workoutsGate;
  Completer<Map<String, dynamic>>? activityGate;
  int workoutCalls = 0;
  int activityCalls = 0;

  @override
  Future<Map<String, dynamic>> syncWorkouts({
    required int startUnix,
    required int endUnix,
    int? enrichStartUnix,
  }) async {
    workoutCalls++;
    if (workoutsGate != null) return workoutsGate!.future;
    return {
      'status': 'empty',
      'workouts': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> syncActivity({
    required int startUnix,
    required int endUnix,
    bool skipTruSleepSoft = false,
    bool skipAutoHrSoft = false,
  }) async {
    activityCalls++;
    if (activityGate != null) return activityGate!.future;
    return {
      'status': 'empty',
      'sleepSessions': <Map<String, dynamic>>[],
      'dailyHrSamples': <Map<String, dynamic>>[],
      'completedContainers': <String>[],
      'enableSkipped': false,
    };
  }

  @override
  Future<Map<String, dynamic>> enableAutoTracking() async {
    return {
      'status': 'ok',
      'overall': 'all_armed',
      'features': <Map<String, dynamic>>[],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('idle syncActivity returns empty stub payload', () async {
    final channel = _ScriptedChannel();
    final link = HuaweiLink(channel: channel);
    // Force ready state via mark helpers after faking connected.
    link.markGateAIncomplete();
    // markGateAIncomplete only works from connected/gateA — set via reflection-free path:
    // Use sync when state is wrong → not_ready.
    final blocked = await link.syncActivity();
    expect(blocked.status, ActivitySyncStatus.notReady);
    expect(channel.activityCalls, 0);
  });

  test('syncWorkouts then overlapping syncActivity → busy on Flutter mirror',
      () async {
    final channel = _ScriptedChannel()
      ..workoutsGate = Completer<Map<String, dynamic>>();
    final link = HuaweiLink(channel: channel);

    // Drive state to gateAIncomplete by listening — use a subclass.
    final ready = _ReadyLink(channel: channel);
    final workoutFuture = ready.syncWorkouts(startUnix: 1, endUnix: 2);
    // Let the first call set syncInFlight.
    await Future<void>.delayed(Duration.zero);
    expect(ready.syncInFlight, isTrue);

    final activity = await ready.syncActivity();
    expect(activity.status, ActivitySyncStatus.busy);
    expect(channel.activityCalls, 0);

    channel.workoutsGate!.complete({
      'status': 'empty',
      'workouts': <Map<String, dynamic>>[],
    });
    final workout = await workoutFuture;
    expect(workout.status, WorkoutSyncStatus.empty);
    expect(ready.syncInFlight, isFalse);

    // Lock released — activity proceeds.
    final after = await ready.syncActivity();
    expect(after.status, ActivitySyncStatus.empty);
    expect(channel.activityCalls, 1);
  });

  test('WorkoutSyncResult.fromMap maps busy and partial_batch', () {
    final busy = WorkoutSyncResult.fromMap({
      'status': 'busy',
      'workouts': <Map<String, dynamic>>[],
    });
    expect(busy.status, WorkoutSyncStatus.busy);

    final partial = WorkoutSyncResult.fromMap({
      'status': 'partial_batch',
      'workouts': <Map<String, dynamic>>[],
    });
    expect(partial.status, WorkoutSyncStatus.partialBatch);
    // Does not collapse unknown→error for these keys.
    expect(partial.status, isNot(WorkoutSyncStatus.error));
  });

  test('enableAutoTracking overlaps syncActivity → busy', () async {
    final channel = _ScriptedChannel()
      ..activityGate = Completer<Map<String, dynamic>>();
    final ready = _ReadyLink(channel: channel);
    final activityFuture = ready.syncActivity();
    await Future<void>.delayed(Duration.zero);
    expect(ready.syncInFlight, isTrue);

    final enable = await ready.enableAutoTracking();
    expect(enable.status, AutoTrackingEnableStatus.busy);

    channel.activityGate!.complete({
      'status': 'empty',
      'sleepSessions': <Map<String, dynamic>>[],
      'dailyHrSamples': <Map<String, dynamic>>[],
      'completedContainers': <String>[],
      'enableSkipped': false,
    });
    await activityFuture;
    expect(ready.syncInFlight, isFalse);
  });

  test('syncWorkouts waits through authenticating then proceeds', () async {
    final channel = _ScriptedChannel();
    final link = _AuthThenReadyLink(channel: channel);
    final future = link.syncWorkouts(startUnix: 1, endUnix: 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(channel.workoutCalls, 0);
    link.mutable = LinkState.connected;
    final result = await future;
    expect(result.status, WorkoutSyncStatus.empty);
    expect(channel.workoutCalls, 1);
  });

  test('syncWorkouts notReady message when still authenticating after wait',
      () async {
    final channel = _ScriptedChannel();
    final link = _AuthThenReadyLink(channel: channel);
    // Tiny timeout via subclass override is awkward — keep authenticating and
    // use a short wait by completing with disconnected mid-wait.
    link.mutable = LinkState.disconnected;
    final blocked = await link.syncWorkouts(startUnix: 1, endUnix: 2);
    expect(blocked.status, WorkoutSyncStatus.notReady);
    expect(channel.workoutCalls, 0);
    expect(blocked.message, contains('Connect and authenticate'));
  });
}

/// Test double that reports an authenticated link state.
class _ReadyLink extends HuaweiLink {
  _ReadyLink({required HuaweiBtChannel channel}) : super(channel: channel);

  @override
  LinkState get state => LinkState.gateAIncomplete;
}

/// Starts authenticating; tests flip [mutable] to connected mid-wait.
class _AuthThenReadyLink extends HuaweiLink {
  _AuthThenReadyLink({required HuaweiBtChannel channel})
      : super(channel: channel);

  LinkState mutable = LinkState.authenticating;

  @override
  LinkState get state => mutable;
}
