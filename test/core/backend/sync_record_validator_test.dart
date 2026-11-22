import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/core/backend/sync_record_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final validator = SyncRecordValidator();
  final now = DateTime(2026, 11, 17, 12);

  SyncRecord workout(Map<String, dynamic> body) => SyncRecord(
        kind: SyncRecordKind.workout,
        id: 'workout_1',
        body: body,
        contentHash: 'x',
      );

  test('workout: valid minimal', () {
    final r = workout({
      'startTime': 1700000000,
      'endTime': 1700003600,
      'durationSec': 3600,
    });
    expect(validator.validate(r, now: now).ok, isTrue);
  });

  test('workout: end before start fails', () {
    final r = workout({
      'startTime': 1700003600,
      'endTime': 1700000000,
      'durationSec': 100,
    });
    expect(validator.validate(r, now: now).reason, 'end_before_start');
  });

  test('workout: hr out of range', () {
    final r = workout({
      'startTime': 1700000000,
      'endTime': 1700003600,
      'durationSec': 3600,
      'hrMin': 10,
      'hrMax': 300,
    });
    expect(validator.validate(r, now: now).reason, 'hr_out_of_range');
  });

  test('dailyTotals: bad day key', () {
    final r = SyncRecord(
      kind: SyncRecordKind.dailyTotals,
      id: 'bad',
      body: {'dayKey': 'nope', 'totalKcal': 100, 'steps': 1},
      contentHash: 'x',
    );
    expect(validator.validate(r, now: now).reason, 'bad_day_key');
  });
}