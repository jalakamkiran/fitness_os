import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/workout_history/domain/swim_invent_guard.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';

void main() {
  group('classifySwimLapInventGuard', () {
    test('keeps normal pool lengths', () {
      const lap = SwimLapMetrics(
        index: 0,
        distanceM: 25,
        durationSec: 22,
        strokes: 34,
        swolf: 46,
        paceSecPer100m: 88,
      );
      expect(
        classifySwimLapInventGuard(lap, poolLengthM: 25).isGarbage,
        isFalse,
      );
    });

    test('filters incomplete length', () {
      const lap = SwimLapMetrics(
        index: 2,
        distanceM: 3,
        durationSec: 2,
        strokes: 2,
        swolf: 4,
      );
      final v = classifySwimLapInventGuard(lap, poolLengthM: 25);
      expect(v.isGarbage, isTrue);
      expect(v.reason, SwimLapFilterReason.incompleteLength);
    });

    test('filters outlier strokes / too-short duration', () {
      const lap = SwimLapMetrics(
        index: 5,
        distanceM: 25,
        durationSec: 1,
        strokes: 180,
        swolf: 181,
      );
      expect(
        classifySwimLapInventGuard(lap, poolLengthM: 25).isGarbage,
        isTrue,
      );
    });
  });

  group('filterSwimLapsForAnalytics', () {
    const raw = [
      SwimLapMetrics(
        index: 0,
        distanceM: 25,
        durationSec: 22,
        strokes: 34,
        swolf: 46,
        paceSecPer100m: 88,
      ),
      SwimLapMetrics(
        index: 1,
        distanceM: 3,
        durationSec: 2,
        strokes: 2,
        swolf: 4,
      ),
      SwimLapMetrics(
        index: 2,
        distanceM: 25,
        durationSec: 24,
        strokes: 36,
        swolf: 49,
        paceSecPer100m: 96,
      ),
      SwimLapMetrics(
        index: 3,
        distanceM: 25,
        durationSec: 1,
        strokes: 180,
        swolf: 181,
      ),
    ];

    test('hides garbage by default', () {
      final active = filterSwimLapsForAnalytics(raw, poolLengthM: 25);
      expect(active.map((l) => l.index), [0, 2]);
      expect(countInventGuardFilteredLaps(raw, poolLengthM: 25), 2);
    });

    test('includeFiltered returns full set', () {
      final all = filterSwimLapsForAnalytics(
        raw,
        poolLengthM: 25,
        includeFiltered: true,
      );
      expect(all.length, 4);
    });
  });
}
