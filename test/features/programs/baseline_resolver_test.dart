import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/programs/domain/baseline_resolver.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/in_session_hr_lock.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed "now" for deterministic 90-day windows.
final _asOf = DateTime.utc(2026, 10, 9, 12);

CanonicalSwimSession _swim({
  required int workoutNumber,
  required int type,
  required int distanceM,
  required int durationSec,
  required DateTime start,
  int? avgPaceSecPer100m,
}) {
  final startUnix = start.toUtc().millisecondsSinceEpoch ~/ 1000;
  final pace = avgPaceSecPer100m ??
      (distanceM > 0 ? (durationSec * 100) ~/ distanceM : null);
  return CanonicalSwimSession(
    workoutNumber: workoutNumber,
    startTime: startUnix,
    endTime: startUnix + durationSec,
    durationSec: durationSec,
    type: type,
    distanceM: distanceM,
    poolLengthM: type == poolSwimWorkoutType ? 25 : null,
    p0: SwimP0Metrics(
      hrCoverage: SwimHrCoverage.absent,
      avgPaceSecPer100m: pace,
      movingAvgPaceSecPer100m: pace,
    ),
  );
}

/// Steady pool swim: ~2:00/100 m wall pace (plausible continuous).
CanonicalSwimSession _pool({
  required int n,
  required int distanceM,
  int daysAgo = 0,
  int? durationSec,
}) {
  final d = durationSec ?? (distanceM * 2); // 2 s/m = 200 s/100 m
  return _swim(
    workoutNumber: n,
    type: poolSwimWorkoutType,
    distanceM: distanceM,
    durationSec: d,
    start: _asOf.subtract(Duration(days: daysAgo)),
  );
}

void main() {
  group('BaselineResolver.resolve', () {
    test('AE1: rich pool history → no forced test, confidence medium/high', () {
      final sessions = [
        _pool(n: 1, distanceM: 1000, daysAgo: 5),
        _pool(n: 2, distanceM: 800, daysAgo: 12),
        _pool(n: 3, distanceM: 900, daysAgo: 20),
        _pool(n: 4, distanceM: 750, daysAgo: 40),
      ];

      final baseline = BaselineResolver().resolve(
        sessions: sessions,
        asOf: _asOf,
      );

      expect(baseline.guidedTestRequired, isFalse);
      expect(baseline.selfReported, isFalse);
      expect(
        baseline.confidence,
        anyOf(BaselineConfidence.medium, BaselineConfidence.high),
      );
      expect(baseline.reason, BaselineReason.richHistory);
      expect(baseline.capacityDistanceM, 1000);
      expect(baseline.sourceWorkoutNumbers, contains(1));
    });

    test('AE2: sparse history → guided test required', () {
      final sessions = [
        _pool(n: 10, distanceM: 600, daysAgo: 7),
        _pool(n: 11, distanceM: 500, daysAgo: 21),
      ];

      final baseline = BaselineResolver().resolve(
        sessions: sessions,
        asOf: _asOf,
      );

      expect(baseline.guidedTestRequired, isTrue);
      expect(
        baseline.confidence,
        anyOf(BaselineConfidence.insufficient, BaselineConfidence.low),
      );
      expect(baseline.reason, BaselineReason.sparseHistory);
      expect(baseline.capacityDistanceM, 600);
    });

    test('empty history → guided test, emptyHistory', () {
      final baseline = BaselineResolver().resolve(
        sessions: const [],
        asOf: _asOf,
      );

      expect(baseline.guidedTestRequired, isTrue);
      expect(baseline.confidence, BaselineConfidence.insufficient);
      expect(baseline.reason, BaselineReason.emptyHistory);
      expect(baseline.capacityDistanceM, 0);
    });

    test('OW-only history ignored for pool baseline', () {
      final sessions = [
        _swim(
          workoutNumber: 20,
          type: openWaterSwimWorkoutType,
          distanceM: 1500,
          durationSec: 3000,
          start: _asOf.subtract(const Duration(days: 3)),
        ),
        _swim(
          workoutNumber: 21,
          type: openWaterSwimWorkoutType,
          distanceM: 2000,
          durationSec: 4000,
          start: _asOf.subtract(const Duration(days: 10)),
        ),
      ];

      final baseline = BaselineResolver().resolve(
        sessions: sessions,
        asOf: _asOf,
      );

      expect(baseline.guidedTestRequired, isTrue);
      expect(baseline.reason, BaselineReason.openWaterOnly);
      expect(baseline.capacityDistanceM, 0);
      expect(baseline.confidence, BaselineConfidence.insufficient);
    });

    test(
      'rest-heavy session does not inflate capacity without confirm',
      () {
        // 500 m / 61 min ≈ 732 s/100 m wall pace — rest-heavy, not capacity.
        final restHeavy = _pool(
          n: 30,
          distanceM: 500,
          daysAgo: 2,
          durationSec: 61 * 60,
        );
        final sessions = [restHeavy];

        final baseline = BaselineResolver().resolve(
          sessions: sessions,
          asOf: _asOf,
        );

        expect(baseline.capacityDistanceM, isNot(500));
        expect(baseline.guidedTestRequired, isTrue);
        expect(
          baseline.reason,
          anyOf(
            BaselineReason.restHeavyUnconfirmed,
            BaselineReason.sparseHistory,
            BaselineReason.emptyHistory,
          ),
        );
        expect(
          baseline.confidence,
          anyOf(BaselineConfidence.insufficient, BaselineConfidence.low),
        );
      },
    );

    test(
      'rest-heavy max ignored when other usable pool swims exist',
      () {
        final sessions = [
          _pool(n: 40, distanceM: 800, daysAgo: 5),
          _pool(n: 41, distanceM: 700, daysAgo: 15),
          _pool(n: 42, distanceM: 750, daysAgo: 25),
          // 2000 m / 90 min ≈ 270 s/100 m wall — rest-heavy, must not win.
          _pool(n: 43, distanceM: 2000, daysAgo: 3, durationSec: 90 * 60),
        ];

        final baseline = BaselineResolver().resolve(
          sessions: sessions,
          asOf: _asOf,
        );

        expect(baseline.guidedTestRequired, isFalse);
        expect(baseline.capacityDistanceM, 800);
        expect(baseline.reason, BaselineReason.richHistory);
        expect(baseline.sourceWorkoutNumbers, isNot(contains(43)));
      },
    );

    test('sessions older than 90 days are ignored', () {
      final sessions = [
        _pool(n: 50, distanceM: 1000, daysAgo: 91),
        _pool(n: 51, distanceM: 900, daysAgo: 100),
        _pool(n: 52, distanceM: 850, daysAgo: 120),
      ];

      final baseline = BaselineResolver().resolve(
        sessions: sessions,
        asOf: _asOf,
      );

      expect(baseline.guidedTestRequired, isTrue);
      expect(baseline.reason, BaselineReason.emptyHistory);
      expect(baseline.capacityDistanceM, 0);
    });

    test('CSS from ~200 m and ~400 m efforts when present', () {
      // T400 = 8:00 (480 s), T200 = 3:40 (220 s)
      // CSS /100 m = (480 - 220) / 2 = 130 s
      final sessions = [
        _pool(n: 60, distanceM: 1000, daysAgo: 4),
        _pool(n: 61, distanceM: 800, daysAgo: 11),
        _pool(n: 62, distanceM: 900, daysAgo: 18),
        _pool(n: 63, distanceM: 400, daysAgo: 6, durationSec: 480),
        _pool(n: 64, distanceM: 200, daysAgo: 6, durationSec: 220),
      ];

      final baseline = BaselineResolver().resolve(
        sessions: sessions,
        asOf: _asOf,
      );

      expect(baseline.cssPaceSecPer100, closeTo(130, 0.01));
      expect(baseline.guidedTestRequired, isFalse);
      expect(baseline.confidence, BaselineConfidence.high);
    });
  });

  group('BaselineResolver.selfReport', () {
    test('AE3: skip test → self-report accepted, confidence low', () {
      final baseline = BaselineResolver.selfReport(
        capacityDistanceM: 800,
        cssPaceSecPer100: 145,
      );

      expect(baseline.capacityDistanceM, 800);
      expect(baseline.cssPaceSecPer100, 145);
      expect(baseline.confidence, BaselineConfidence.low);
      expect(baseline.selfReported, isTrue);
      expect(baseline.guidedTestRequired, isFalse);
      expect(baseline.reason, BaselineReason.selfReported);
    });
  });

  group('BaselineResolver.prescribeGuidedTest', () {
    test('continuous swim near capacity; CSS protocol when pace goal', () {
      const current = Baseline(
        capacityDistanceM: 1000,
        confidence: BaselineConfidence.low,
        reason: BaselineReason.sparseHistory,
        guidedTestRequired: true,
      );

      final rx = BaselineResolver().prescribeGuidedTest(
        current: current,
        paceGoalPresent: true,
      );

      expect(rx.continuousDistanceM, inInclusiveRange(800, 1200));
      expect(rx.includeCssProtocol, isTrue);
      expect(rx.css400DistanceM, 400);
      expect(rx.css200DistanceM, 200);
    });

    test('no CSS protocol when no pace goal', () {
      const current = Baseline(
        capacityDistanceM: 500,
        confidence: BaselineConfidence.insufficient,
        reason: BaselineReason.emptyHistory,
        guidedTestRequired: true,
      );

      final rx = BaselineResolver().prescribeGuidedTest(
        current: current,
        paceGoalPresent: false,
      );

      expect(rx.includeCssProtocol, isFalse);
      expect(rx.continuousDistanceM, greaterThan(0));
    });
  });
}
