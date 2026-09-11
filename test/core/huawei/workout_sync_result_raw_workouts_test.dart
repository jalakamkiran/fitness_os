import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WorkoutSyncResult retains raw leftoverBodies for U2', () {
    final r = WorkoutSyncResult.fromMap({
      'status': 'ok',
      'workouts': [
        {
          'number': 1,
          'startTime': 10,
          'endTime': 20,
          'durationSec': 10,
          'type': 2,
          'observedType': 2,
          'leftoverBodies': [
            {'id': 0x66, 'len': 2, 'bodyBase64': 'qq=='},
          ],
          'dataPages': [
            {
              'index': 0,
              'leftoverBodies': [
                {'id': 0x7a, 'len': 1, 'bodyBase64': 'AQ=='},
              ],
            },
          ],
        },
      ],
    });
    expect(r.rawWorkouts, isNotNull);
    expect(r.rawWorkouts!.single['leftoverBodies'], isNotEmpty);
    expect(r.rawWorkouts!.single['observedType'], 2);
    expect(r.rawWorkouts!.single['dataPages'], isNotEmpty);
    expect(r.workouts.single.number, 1);
    final bodies = WorkoutChannelRawKeys.parseLeftoverBodies(
      r.rawWorkouts!.single['leftoverBodies'],
    );
    expect(bodies.single.id, 0x66);
    expect(bodies.single.bodyBase64, 'qq==');
  });
}
