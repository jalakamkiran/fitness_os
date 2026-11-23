import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/core/backend/sync_record_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final validator = SyncRecordValidator();
  final now = DateTime(2026, 11, 23, 12);

  SyncRecord sleep(Map<String, dynamic> body) => SyncRecord(
        kind: SyncRecordKind.sleep,
        id: 'sleep_test',
        body: body,
        contentHash: 'x',
      );

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

  test('sleep: valid ~7h night with score and SpO2', () {
    final body = {
      'beginUnix': 1700000000,
      'endUnix': 1700025200,
      'sleepScore': 70,
      'avgSpO2': 96,
    };
    SyncRecordValidator.sanitizeSleepBody(body);
    final r = sleep(body);
    expect(validator.validate(r, now: now).ok, isTrue);
  });

  test('sleep: inflated stage sum is not quarantined after sanitize', () {
    const begin = 1700000000;
    const end = begin + 7 * 3600;
    final spanMin = (end - begin) ~/ 60;
    final stages = List.generate(
      60,
      (i) => {
        'timestampUnix': begin + i * 10,
        'durationMin': 1,
        'stage': 1,
      },
    );
    final body = {
      'beginUnix': begin,
      'endUnix': end,
      'stages': stages,
    };
    SyncRecordValidator.sanitizeSleepBody(body);
    final r = sleep(body);
    expect(validator.validate(r, now: now).ok, isTrue);
    expect(body['beginUnix'], begin);
    expect(body['endUnix'], end);
    final outStages = body['stages'] as List?;
    if (outStages != null) {
      final sum = outStages.fold<int>(
        0,
        (s, st) => s + ((st as Map)['durationMin'] as num).toInt(),
      );
      expect(sum, lessThanOrEqualTo(spanMin + SyncRecordValidator.stageSpanSlackMin));
    }
  });

  test('sleep: sentinel enrich does not quarantine', () {
    final body = {
      'beginUnix': 1700000000,
      'endUnix': 1700025200,
      'avgSpO2': 255,
      'avgHr': 0,
      'avgBreathRate': 255,
      'sleepScore': 255,
    };
    SyncRecordValidator.sanitizeSleepBody(body);
    final r = sleep(body);
    expect(validator.validate(r, now: now).ok, isTrue);
    expect(body.containsKey('avgSpO2'), isFalse);
    expect(body.containsKey('avgHr'), isFalse);
    expect(body.containsKey('sleepScore'), isFalse);
  });

  test('sleep: score 0 is ok', () {
    final body = {
      'beginUnix': 1700000000,
      'endUnix': 1700025200,
      'sleepScore': 0,
    };
    SyncRecordValidator.sanitizeSleepBody(body);
    expect(validator.validate(sleep(body), now: now).ok, isTrue);
    expect(body['sleepScore'], 0);
  });

  test('sleep: hard failure end_before_start', () {
    final body = {'beginUnix': 1700025200, 'endUnix': 1700000000};
    expect(validator.validate(sleep(body), now: now).reason, 'end_before_start');
  });

  test('sleep: hard failure span_too_long', () {
    final body = {
      'beginUnix': 1700000000,
      'endUnix': 1700000000 + 21 * 3600,
    };
    expect(validator.validate(sleep(body), now: now).reason, 'span_too_long');
  });

  test('sleep: hard failure missing_fields', () {
    expect(
      validator.validate(sleep({'beginUnix': 1}), now: now).reason,
      'missing_fields',
    );
  });
}