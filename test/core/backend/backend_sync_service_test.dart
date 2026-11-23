import 'dart:async';
import 'dart:convert';

import 'package:fitness_os/core/backend/backend_sync_service.dart';
import 'package:fitness_os/core/backend/local_sync_snapshot.dart';
import 'package:fitness_os/core/backend/sync_ledger_store.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/core/backend/sync_record_validator.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/backend_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackendTransport transport;
  late InMemorySyncLedgerStore ledger;
  late FakeWorkoutRepo workouts;
  late FakeVitalsRepo vitals;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    transport = FakeBackendTransport();
    ledger = InMemorySyncLedgerStore();
    workouts = FakeWorkoutRepo();
    vitals = FakeVitalsRepo();
  });

  BackendSyncService buildService() => BackendSyncService(
        transport: transport,
        ledger: ledger,
        snapshot: LocalSyncSnapshot(workouts: workouts, vitals: vitals),
        validator: SyncRecordValidator(),
        prefs: prefs,
        telemetry: RecordingTelemetry(),
        isEnabled: () => true,
        now: () => DateTime(2026, 11, 17, 12),
      );

  test('first push sends records; second with no changes skips HTTP', () async {
    workouts.workouts = [
      WorkoutSummary(
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
      ),
    ];
    final svc = buildService();
    final first = await svc.push(SyncTrigger.open);
    expect(first.ok, isTrue);
    expect(transport.capturedBodies.length, 1);

    transport.capturedBodies.clear();
    final second = await svc.push(SyncTrigger.open);
    expect(second.ok, isTrue);
    expect(transport.capturedBodies, isEmpty);
  });

  test('queueing: in-flight push coalesces to one follow-up HTTP', () async {
    workouts.workouts = [
      WorkoutSummary(
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
        calories: 50,
      ),
    ];
    final gate = Completer<void>();
    transport.resetBlockState();
    transport.blockCompleter = gate;
    final svc = buildService();
    final first = svc.push(SyncTrigger.open);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    workouts.workouts = [
      WorkoutSummary(
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
        calories: 99,
      ),
    ];
    final q1 = await svc.push(SyncTrigger.postWatch);
    final q2 = await svc.push(SyncTrigger.manual);
    expect(q1.queued, isTrue);
    expect(q2.queued, isTrue);
    gate.complete();
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // First HTTP + exactly one coalesced follow-up (not three).
    expect(transport.capturedBodies.length, 2);
  });

  test('push sends new sleep and workout, not already-synced sleep', () async {
    vitals.sleep = const [
      SleepSessionSummary(beginUnix: 1700000000, endUnix: 1700025200),
      SleepSessionSummary(beginUnix: 1700100000, endUnix: 1700125200),
    ];
    workouts.workouts = [
      WorkoutSummary(
        number: 2,
        type: 2,
        startTime: 1700050000,
        endTime: 1700053600,
        durationSec: 3600,
      ),
    ];
    final snapshot = LocalSyncSnapshot(workouts: workouts, vitals: vitals);
    final built = await snapshot.build();
    final older = built!.firstWhere((r) => r.id == 'sleep_1700000000');
    await ledger.save(SyncLedgerData(entries: {
      older.ledgerKey: LedgerEntry(
        state: LedgerState.synced,
        hash: older.contentHash,
        updatedAtMs: 1,
        ackedAtMs: 1,
      ),
    }));

    final svc = buildService();
    await svc.push(SyncTrigger.open);
    expect(transport.capturedBodies.length, 1);
    final payload = jsonDecode(utf8.decode(transport.capturedBodies.single)) as Map;
    final sleepList = payload['sleep'] as List;
    final workoutList = payload['workouts'] as List;
    expect(sleepList.length, 1);
    expect((sleepList.single as Map)['beginUnix'], 1700100000);
    expect(workoutList.length, 1);
  });

  test('soft-quarantined sleep is resent and marked synced on legacy 200', () async {
    vitals.sleep = const [
      SleepSessionSummary(beginUnix: 1700000000, endUnix: 1700025200),
    ];
    final snapshot = LocalSyncSnapshot(workouts: workouts, vitals: vitals);
    final built = await snapshot.build();
    final record = built!.single;
    await ledger.save(SyncLedgerData(entries: {
      record.ledgerKey: LedgerEntry(
        state: LedgerState.quarantined,
        hash: record.contentHash,
        updatedAtMs: 1,
        reason: 'stage_sum_exceeds_span',
      ),
    }));

    final svc = buildService();
    final out = await svc.push(SyncTrigger.open);
    expect(out.ok, isTrue);
    expect(transport.capturedBodies.length, 1);
    final payload = jsonDecode(utf8.decode(transport.capturedBodies.single)) as Map;
    expect((payload['sleep'] as List).length, 1);

    final ledgerAfter = await ledger.load();
    expect(
      ledgerAfter.entries[record.ledgerKey]!.state,
      LedgerState.synced,
    );
  });

  test('soft-quarantined sleep resets to pending on next push', () async {
    vitals.sleep = const [
      SleepSessionSummary(beginUnix: 1700000000, endUnix: 1700025200),
    ];
    final snapshot = LocalSyncSnapshot(workouts: workouts, vitals: vitals);
    final built = await snapshot.build();
    final record = built!.single;
    await ledger.save(SyncLedgerData(entries: {
      record.ledgerKey: LedgerEntry(
        state: LedgerState.quarantined,
        hash: record.contentHash,
        updatedAtMs: 1,
        reason: 'spo2_out_of_range',
      ),
    }));

    final svc = buildService();
    await svc.push(SyncTrigger.open);
    final ledgerAfter = await ledger.load();
    expect(
      ledgerAfter.entries[record.ledgerKey]!.state,
      isNot(LedgerState.quarantined),
    );
  });

  test('quarantined workouts are not reset', () async {
    workouts.workouts = [
      WorkoutSummary(
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
      ),
    ];
    final snapshot = LocalSyncSnapshot(workouts: workouts, vitals: vitals);
    final built = await snapshot.build();
    final record = built!.single;
    await ledger.save(SyncLedgerData(entries: {
      record.ledgerKey: LedgerEntry(
        state: LedgerState.quarantined,
        hash: record.contentHash,
        updatedAtMs: 1,
        reason: 'duration_exceeds_span',
      ),
    }));

    final svc = buildService();
    await svc.push(SyncTrigger.open);
    final ledgerAfter = await ledger.load();
    expect(
      ledgerAfter.entries[record.ledgerKey]!.state,
      LedgerState.quarantined,
    );
    expect(transport.capturedBodies, isEmpty);
  });

  test('postWatch after open is not cooldown-blocked', () async {
    workouts.workouts = [
      WorkoutSummary(
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
        calories: 100,
      ),
    ];
    final svc = buildService();
    await svc.push(SyncTrigger.open);
    workouts.workouts = [
      WorkoutSummary(
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
        calories: 200,
      ),
    ];
    await svc.push(SyncTrigger.postWatch);
    expect(transport.capturedBodies.length, 2);
  });
}