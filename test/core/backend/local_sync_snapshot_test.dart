import 'package:fitness_os/core/backend/local_sync_snapshot.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/backend_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('snapshot omits sentinel enrich but keeps begin/end', () async {
    final vitals = FakeVitalsRepo();
    vitals.sleep = const [
      SleepSessionSummary(beginUnix: 1700000000, endUnix: 1700025200),
    ];
    vitals.truSleepByBegin = {
      1700000000: TruSleepSequenceSession(
        beginUnix: 1700000000,
        endUnix: 1700025200,
        avgOxygenSaturation: 255,
        avgHeartRate: 0,
        sleepScore: 72,
      ),
    };

    final snapshot = LocalSyncSnapshot(
      workouts: FakeWorkoutRepo(),
      vitals: vitals,
    );
    final records = await snapshot.build();
    expect(records, isNotNull);
    final sleep = records!.single;
    expect(sleep.body['beginUnix'], 1700000000);
    expect(sleep.body['endUnix'], 1700025200);
    expect(sleep.body['sleepScore'], 72);
    expect(sleep.body.containsKey('avgSpO2'), isFalse);
    expect(sleep.body.containsKey('avgHr'), isFalse);
  });
}