import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/sleep_analytics.dart';

void main() {
  group('sleep analytics', () {
    test('mean and stdDev need at least two values', () {
      expect(meanOf([84]), isNull);
      expect(stdDevOf([84]), isNull);
      expect(meanOf([80, 84]), 82);
      expect(stdDevOf([80, 84]), closeTo(2.828, 0.01));
    });

    test('recentOvernightSessions filters naps and window', () {
      final now = DateTime(2026, 9, 12, 18);
      final overnight = SleepSessionSummary(
        beginUnix: DateTime(2026, 9, 11, 23, 54).millisecondsSinceEpoch ~/ 1000,
        endUnix: DateTime(2026, 9, 12, 9, 31).millisecondsSinceEpoch ~/ 1000,
      );
      final nap = SleepSessionSummary(
        beginUnix: DateTime(2026, 9, 12, 14).millisecondsSinceEpoch ~/ 1000,
        endUnix: DateTime(2026, 9, 12, 14, 40).millisecondsSinceEpoch ~/ 1000,
      );
      final old = SleepSessionSummary(
        beginUnix: DateTime(2026, 8, 1, 23).millisecondsSinceEpoch ~/ 1000,
        endUnix: DateTime(2026, 8, 2, 6).millisecondsSinceEpoch ~/ 1000,
      );
      final got = recentOvernightSessions(
        [overnight, nap, old],
        now: now,
        dayCount: 7,
      );
      expect(got, [overnight]);
    });

    test('recentOvernightSessions includes same-calendar-day overnight', () {
      final now = DateTime(2026, 10, 7, 18);
      final sameDay = SleepSessionSummary(
        beginUnix:
            DateTime(2026, 10, 7, 1, 36).millisecondsSinceEpoch ~/ 1000,
        endUnix: DateTime(2026, 10, 7, 8, 11).millisecondsSinceEpoch ~/ 1000,
      );
      final got = recentOvernightSessions(
        [sameDay],
        now: now,
        dayCount: 7,
      );
      expect(got, [sameDay]);
    });

    test('recentOvernightSessions coalesces fragmented prefs', () {
      final now = DateTime(2026, 10, 8, 12);
      final a = SleepSessionSummary(
        beginUnix:
            DateTime(2026, 10, 8, 0, 30).millisecondsSinceEpoch ~/ 1000,
        endUnix: DateTime(2026, 10, 8, 3, 10).millisecondsSinceEpoch ~/ 1000,
      );
      final b = SleepSessionSummary(
        beginUnix:
            DateTime(2026, 10, 8, 3, 19).millisecondsSinceEpoch ~/ 1000,
        endUnix: DateTime(2026, 10, 8, 7, 0).millisecondsSinceEpoch ~/ 1000,
      );
      final got = recentOvernightSessions([a, b], now: now, dayCount: 7);
      expect(got, hasLength(1));
      expect(got.single.beginUnix, a.beginUnix);
      expect(got.single.endUnix, b.endUnix);
    });

    test('stageMinutesOf aggregates wire types', () {
      final mins = stageMinutesOf([
        const SleepStageSummary(timestampUnix: 1, durationMin: 10, wireType: 1),
        const SleepStageSummary(timestampUnix: 2, durationMin: 20, wireType: 2),
        const SleepStageSummary(timestampUnix: 3, durationMin: 15, wireType: 3),
        const SleepStageSummary(timestampUnix: 4, durationMin: 5, wireType: 4),
      ]);
      expect(mins.light, 10);
      expect(mins.deep, 20);
      expect(mins.rem, 15);
      expect(mins.awake, 5);
    });

    test('architecture note deep early rem late', () {
      final stages = <SleepStageSummary>[
        const SleepStageSummary(timestampUnix: 1, durationMin: 60, wireType: 2),
        const SleepStageSummary(timestampUnix: 2, durationMin: 40, wireType: 1),
        const SleepStageSummary(timestampUnix: 3, durationMin: 50, wireType: 3),
      ];
      expect(
        sleepArchitectureNote(stages),
        contains('Deep early'),
      );
    });

    test('timing day hasData', () {
      final day = SleepTimingDay(
        endDay: DateTime(2026, 9, 12),
        bedUnix: 100,
        asleepUnix: 200,
        wakeUnix: 300,
        riseUnix: 320,
      );
      expect(day.hasData, isTrue);
      expect(
        SleepTimingDay(
          endDay: DateTime(2026, 9, 12),
          bedUnix: 0,
          asleepUnix: 0,
          wakeUnix: 0,
          riseUnix: 0,
        ).hasData,
        isFalse,
      );
    });
  });
}
