import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/sleep_hr_window.dart';

void main() {
  group('sleepHrDayKeys', () {
    test('same-day window returns one key', () {
      final begin = DateTime(2024, 6, 2, 1).millisecondsSinceEpoch ~/ 1000;
      final end = DateTime(2024, 6, 2, 6).millisecondsSinceEpoch ~/ 1000;
      expect(
        sleepHrDayKeys(beginUnix: begin, endUnix: end),
        ['2024-06-02'],
      );
    });

    test('overnight span returns both dayKeys', () {
      final begin = DateTime(2024, 6, 1, 23).millisecondsSinceEpoch ~/ 1000;
      final end = DateTime(2024, 6, 2, 6).millisecondsSinceEpoch ~/ 1000;
      expect(
        sleepHrDayKeys(beginUnix: begin, endUnix: end),
        ['2024-06-01', '2024-06-02'],
      );
    });

    test('inverted or empty range returns empty', () {
      expect(sleepHrDayKeys(beginUnix: 100, endUnix: 100), isEmpty);
      expect(sleepHrDayKeys(beginUnix: 200, endUnix: 100), isEmpty);
      expect(sleepHrDayKeys(beginUnix: 0, endUnix: 100), isEmpty);
    });
  });

  group('windowSleepHrSamples', () {
    test('filters inclusive window; excludes outside', () {
      const samples = [
        DailyHrSample(timestampUnix: 90, bpm: 50),
        DailyHrSample(timestampUnix: 100, bpm: 60),
        DailyHrSample(timestampUnix: 150, bpm: 70),
        DailyHrSample(timestampUnix: 200, bpm: 80),
        DailyHrSample(timestampUnix: 250, bpm: 90),
      ];
      final window = windowSleepHrSamples(
        samples: samples,
        beginUnix: 100,
        endUnix: 200,
      );
      expect(window.map((s) => s.bpm).toList(), [60, 70, 80]);
    });

    test('empty / missing / inverted → empty', () {
      expect(
        windowSleepHrSamples(samples: const [], beginUnix: 1, endUnix: 2),
        isEmpty,
      );
      expect(
        windowSleepHrSamples(
          samples: const [DailyHrSample(timestampUnix: 1, bpm: 60)],
          beginUnix: 2,
          endUnix: 1,
        ),
        isEmpty,
      );
    });
  });

  group('sleepHrStats', () {
    test('computes min avg max', () {
      final stats = sleepHrStats(const [
        DailyHrSample(timestampUnix: 1, bpm: 60),
        DailyHrSample(timestampUnix: 2, bpm: 70),
        DailyHrSample(timestampUnix: 3, bpm: 80),
      ]);
      expect(stats!.minBpm, 60);
      expect(stats.avgBpm, 70);
      expect(stats.maxBpm, 80);
    });

    test('empty → null', () {
      expect(sleepHrStats(const []), isNull);
    });
  });

  group('SleepSessionSummary stages DTO', () {
    test('fromMap round-trips stages; toJson stays lean', () {
      final session = SleepSessionSummary.fromMap({
        'beginUnix': 100,
        'endUnix': 200,
        'wireType': 1,
        'stages': [
          {'timestampUnix': 100, 'durationMin': 30, 'wireType': 1},
          {'timestampUnix': 100 + 30 * 60, 'durationMin': 40, 'wireType': 3},
        ],
      });
      expect(session.stages, hasLength(2));
      expect(session.toJson().containsKey('stages'), isFalse);
      expect(session.toJsonWithStages()['stages'], hasLength(2));
      expect(session.mergeKey, '100:200:1');
    });
  });
}
