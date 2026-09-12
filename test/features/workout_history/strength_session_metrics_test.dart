import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/strength_session_metrics.dart';

void main() {
  WorkoutSummary strength({
    int number = 64,
    int start = 1000,
    int durationSec = 3180,
    int? calories = 200,
    int? load = 12,
    int? recoveryTime = 60,
    int? aerobic = 9,
    int? anaerobic = 0,
    int? hrMin = 86,
    int? hrMax = 146,
  }) {
    return WorkoutSummary(
      number: number,
      startTime: start,
      endTime: start + durationSec,
      durationSec: durationSec,
      type: 140,
      calories: calories,
      load: load,
      recoveryTime: recoveryTime,
      aerobicEffect: aerobic,
      anaerobicEffect: anaerobic,
      hrMin: hrMin,
      hrMax: hrMax,
    );
  }

  test('formats recovery minutes for product UI', () {
    expect(formatRecoveryMinutes(null), isNull);
    expect(formatRecoveryMinutes(0), '0m');
    expect(formatRecoveryMinutes(45), '45m');
    expect(formatRecoveryMinutes(60), '1h');
    expect(formatRecoveryMinutes(90), '1h 30m');
  });

  test('derives #64-style labels without inventing recovery %', () {
    final m = StrengthSessionMetrics(strength());
    expect(m.durationLabel, '53m');
    expect(m.caloriesLabel, '200');
    expect(m.hrRangeLabel, '86–146');
    expect(m.loadLabel, '12');
    expect(m.recoveryTimeLabel, '1h');
    expect(m.aerobicLabel, '9');
    expect(m.anaerobicLabel, '0');
    expect(m.caloriesPerMinLabel, '3.8');
    expect(m.loadPerHourLabel, '13.6');
  });

  test('omits missing scalars (null ≠ zero)', () {
    final m = StrengthSessionMetrics(
      strength(
        load: null,
        recoveryTime: null,
        aerobic: null,
        anaerobic: null,
        calories: null,
        hrMin: null,
        hrMax: null,
      ),
    );
    expect(m.loadLabel, isNull);
    expect(m.recoveryTimeLabel, isNull);
    expect(m.aerobicLabel, isNull);
    expect(m.anaerobicLabel, isNull);
    expect(m.caloriesLabel, isNull);
    expect(m.hrRangeLabel, isNull);
    expect(m.hasImpact, isFalse);
  });

  test('recentStrengthLoads keeps chronological window ending at current', () {
    final sessions = [
      for (var i = 1; i <= 10; i++)
        strength(number: i, start: i * 100, load: i),
    ];
    final current = sessions[8]; // number 9
    final recent = recentStrengthLoads(current: current, all: sessions, limit: 8);
    expect(recent.map((w) => w.number).toList(), [2, 3, 4, 5, 6, 7, 8, 9]);
  });

  test('recentStrengthLoads falls back to current alone when missing', () {
    final current = strength(number: 99, start: 9999, load: 5);
    final recent = recentStrengthLoads(
      current: current,
      all: [strength(number: 1, start: 100, load: 3)],
    );
    expect(recent, [current]);
  });
}
