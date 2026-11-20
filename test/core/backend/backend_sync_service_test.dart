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