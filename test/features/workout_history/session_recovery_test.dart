import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/session_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

WorkoutSummary _w({
  int? recoveryTime,
  int durationSec = 3600,
  int type = 140,
  int? aerobicEffect,
  int? anaerobicEffect,
  int? load,
  int? hrPeak,
}) {
  return WorkoutSummary(
    number: 1,
    startTime: 1,
    endTime: 1 + durationSec,
    durationSec: durationSec,
    type: type,
    recoveryTime: recoveryTime,
    aerobicEffect: aerobicEffect,
    anaerobicEffect: anaerobicEffect,
    load: load,
    hrPeak: hrPeak,
  );
}

void main() {
  group('resolveSessionRecovery', () {
    test('watch minutes win including zero', () {
      final watch = resolveSessionRecovery(_w(recoveryTime: 960));
      expect(watch!.hours, 16);
      expect(watch.source, SessionRecoverySource.watch);

      final zero = resolveSessionRecovery(_w(recoveryTime: 0));
      expect(zero!.hours, 0);
      expect(zero.source, SessionRecoverySource.watch);
    });

    test('null recovery with duration 0 refuses estimate', () {
      expect(resolveSessionRecovery(_w(durationSec: 0)), isNull);
    });

    test('swim without recovery estimates from duration × moderate', () {
      final r = resolveSessionRecovery(
        _w(type: 6, durationSec: 45 * 60),
      );
      expect(r, isNotNull);
      expect(r!.source, SessionRecoverySource.estimated);
      expect(r.hours, closeTo(0.75 * kIntensityModerate, 0.01));
      expect(r.hours, greaterThanOrEqualTo(kEstimateHoursMin));
      expect(r.hours, lessThanOrEqualTo(kEstimateHoursMax));
    });

    test('TE band maps wire ÷10', () {
      final r = resolveSessionRecovery(
        _w(aerobicEffect: 28, durationSec: 1800),
      );
      expect(r!.source, SessionRecoverySource.estimated);
      expect(r.hours, 24); // TE 2.8 → 24h band
    });

    test('watch path is not clamped by estimate bounds', () {
      final r = resolveSessionRecovery(_w(recoveryTime: 90)); // 1.5h
      expect(r!.hours, 1.5);
      expect(r.source, SessionRecoverySource.watch);
    });
  });
}
