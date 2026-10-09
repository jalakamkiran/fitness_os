import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/overall_recovery_hours.dart';
import 'package:flutter_test/flutter_test.dart';

WorkoutSummary _session({
  required int endUnix,
  int durationSec = 3600,
  int? recoveryTime,
  int type = 140,
}) {
  return WorkoutSummary(
    number: 1,
    startTime: endUnix - durationSec,
    endTime: endUnix,
    durationSec: durationSec,
    type: type,
    recoveryTime: recoveryTime,
  );
}

void main() {
  group('composeOverallRecoveryHours', () {
    test('insufficient when no sessions sleep or activity', () {
      final now = DateTime(2026, 10, 9, 10);
      final r = composeOverallRecoveryHours(workouts: const [], now: now);
      expect(r.insufficientData, isTrue);
      expect(r.displayLabel, '—');
    });

    test('rest morning leftover + sleep shows hours (AE3)', () {
      final now = DateTime(2026, 10, 9, 8);
      final yesterdayEnd =
          DateTime(2026, 10, 8, 20).millisecondsSinceEpoch ~/ 1000;
      final r = composeOverallRecoveryHours(
        workouts: [
          _session(endUnix: yesterdayEnd, recoveryTime: 16 * 60),
        ],
        now: now,
        sleepDurationSec: 7 * 3600,
      );
      expect(r.insufficientData, isFalse);
      // 16h from 20:00 → 08:00 next day = 12h elapsed → ~4h left
      expect(r.hoursRemaining, closeTo(4, 0.1));
      expect(r.displayLabel, '4h');
    });

    test('wall-clock decay reduces remaining', () {
      final end = DateTime(2026, 10, 9, 6).millisecondsSinceEpoch ~/ 1000;
      final atSeven = composeOverallRecoveryHours(
        workouts: [_session(endUnix: end, recoveryTime: 10 * 60)],
        now: DateTime(2026, 10, 9, 7),
      );
      final atNine = composeOverallRecoveryHours(
        workouts: [_session(endUnix: end, recoveryTime: 10 * 60)],
        now: DateTime(2026, 10, 9, 9),
      );
      expect(atSeven.hoursRemaining!, greaterThan(atNine.hoursRemaining!));
    });

    test('exhausted leftover displays 0h not dash', () {
      final end = DateTime(2026, 10, 8, 8).millisecondsSinceEpoch ~/ 1000;
      final r = composeOverallRecoveryHours(
        workouts: [_session(endUnix: end, recoveryTime: 2 * 60)],
        now: DateTime(2026, 10, 9, 10),
        sleepDurationSec: 8 * 3600,
      );
      expect(r.insufficientData, isFalse);
      expect(r.hoursRemaining, 0);
      expect(r.displayLabel, '0h');
    });

    test('short sleep adds capped hours', () {
      final end = DateTime(2026, 10, 9, 6).millisecondsSinceEpoch ~/ 1000;
      final good = composeOverallRecoveryHours(
        workouts: [_session(endUnix: end, recoveryTime: 8 * 60)],
        now: DateTime(2026, 10, 9, 7),
        sleepDurationSec: 8 * 3600,
      );
      final short = composeOverallRecoveryHours(
        workouts: [_session(endUnix: end, recoveryTime: 8 * 60)],
        now: DateTime(2026, 10, 9, 7),
        sleepDurationSec: 4 * 3600,
      );
      expect(short.hoursRemaining!, greaterThan(good.hoursRemaining!));
    });
  });
}
