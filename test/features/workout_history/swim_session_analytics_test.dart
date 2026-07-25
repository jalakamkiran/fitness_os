import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';

void main() {
  group('analyzeSwimSession', () {
    test('null when fewer than 2 paced intervals', () {
      final p0 = computeSwimP0(
        durationSec: 100,
        segmentLaps: const [
          SwimLapMetrics(index: 0, distanceM: 25, durationSec: 20),
        ],
      );
      expect(analyzeSwimSession(p0), isNull);
    });

    test('detects pace decay and length PARTIAL claim on #11-shaped set', () {
      final p0 = computeSwimP0(
        durationSec: 3683,
        distanceM: 500,
        strokes: 350,
        avgSwolf: 165,
        laps: 20,
        hrMin: 90,
        hrMax: 140,
        sampleCount: 0,
        segmentLaps: const [
          SwimLapMetrics(index: 0, distanceM: 25, durationSec: 11, strokes: 124, swolf: 135),
          SwimLapMetrics(index: 1, distanceM: 25, durationSec: 12, strokes: 36, swolf: 48),
          SwimLapMetrics(index: 2, distanceM: 25, durationSec: 11, strokes: 69, swolf: 80),
          SwimLapMetrics(index: 3, distanceM: 25, durationSec: 17, strokes: 71, swolf: 88),
          SwimLapMetrics(index: 4, distanceM: 25, durationSec: 8, strokes: 323, swolf: 331),
          SwimLapMetrics(index: 5, distanceM: 25, durationSec: 22, strokes: 124, swolf: 146),
        ],
      );

      final a = analyzeSwimSession(p0)!;
      expect(a.paceDecayPct, isNotNull);
      expect(a.paceCvPct, isNotNull);
      expect(a.swolfDelta, isNotNull);
      expect(a.showHrPhysiology, isFalse);
      expect(a.claims.any((c) => c.id == 'pace_decay'), isTrue);
      expect(a.claims.any((c) => c.id == 'pace_consistency'), isTrue);
      expect(a.claims.any((c) => c.id == 'swolf_trend'), isTrue);
      expect(a.claims.any((c) => c.id == 'length_coverage'), isTrue);
      expect(
        a.claims.firstWhere((c) => c.id == 'length_coverage').confidence,
        SwimConfidence.low,
      );
      expect(a.intervalEfficiencies, hasLength(6));
      expect(a.intervalEfficiencies.first.strokesPer25m, closeTo(124, 0.01));
    });

    test('clean 8-interval set — high confidence, no length claim, HR hidden', () {
      final laps = List.generate(
        8,
        (i) => SwimLapMetrics(
          index: i,
          distanceM: 25,
          durationSec: 20 + (i < 4 ? 0 : 1), // slight decay
          strokes: 18,
          swolf: 38 + (i < 4 ? 0 : 1),
        ),
      );
      final p0 = computeSwimP0(
        durationSec: 170,
        distanceM: 200,
        strokes: 144,
        avgSwolf: 39,
        laps: 8,
        segmentLaps: laps,
      );

      final a = analyzeSwimSession(p0)!;
      expect(a.showHrPhysiology, isFalse);
      expect(a.claims.any((c) => c.id == 'length_coverage'), isFalse);
      expect(a.paceDecayPct, greaterThan(0));
      final decay = a.claims.firstWhere((c) => c.id == 'pace_decay');
      expect(decay.confidence, SwimConfidence.high);
    });

    test('shows HR claim only when sample stream present', () {
      final p0 = computeSwimP0(
        durationSec: 100,
        distanceM: 50,
        sampleCount: 10,
        segmentLaps: const [
          SwimLapMetrics(index: 0, distanceM: 25, durationSec: 20, swolf: 40),
          SwimLapMetrics(index: 1, distanceM: 25, durationSec: 22, swolf: 42),
        ],
      );
      final a = analyzeSwimSession(p0)!;
      expect(a.showHrPhysiology, isTrue);
      expect(a.claims.any((c) => c.id == 'hr_samples'), isTrue);
    });
  });
}
