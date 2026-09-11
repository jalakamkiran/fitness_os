import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';

/// Sibling invent-guard coverage for Run detail (AE3 / AE4).
///
/// Named VO / balance / zone-minute tiles must stay absent without native
/// decoded fields — never invent from leftovers or empty streams.
void main() {
  group('RunInventGuard', () {
    test('default Outdoor summary invents nothing', () {
      const w = WorkoutSummary(
        number: 1,
        startTime: 10,
        endTime: 20,
        durationSec: 10,
        type: 2,
        steps: 100,
      );
      final m = RunSessionMetrics.fromSummary(w);
      expect(RunInventGuard.showsVo2(m), isFalse);
      expect(RunInventGuard.showsVerticalOscillation(m), isFalse);
      expect(RunInventGuard.showsBalance(m), isFalse);
      expect(RunInventGuard.showsNativeZoneMinutes(m), isFalse);
      expect(RunInventGuard.showsThisRunTraining(m), isFalse);
    });

    test('explicit decoded fields unlock named tiles', () {
      const m = RunSessionMetrics(
        vo2Max: 48.5,
        verticalOscillationMm: 8.2,
        balancePct: 49,
        hrZoneMinutes: [5, 10, 12],
        recoverySec: 3600,
        aerobicEffect: 2.5,
        sessionLoad: 80,
      );
      expect(RunInventGuard.showsVo2(m), isTrue);
      expect(RunInventGuard.showsVerticalOscillation(m), isTrue);
      expect(RunInventGuard.showsBalance(m), isTrue);
      expect(RunInventGuard.showsNativeZoneMinutes(m), isTrue);
      expect(RunInventGuard.showsThisRunTraining(m), isTrue);
    });

    test('zone type alone is not invented minutes', () {
      const m = RunSessionMetrics(hrZoneType: 'max');
      expect(m.hasNativeZones, isTrue);
      expect(RunInventGuard.showsNativeZoneMinutes(m), isFalse);
    });

    test('opaque leftover pages do not decode into stream points', () {
      expect(
        decodeRunSamplePoints(const [
          PeeledPageBodies(
            index: 0,
            bodies: [
              LeftoverTlvBody(id: 0x66, len: 8, bodyBase64: 'AAAAAAAAAAA='),
            ],
          ),
        ]),
        isEmpty,
      );
    });
  });
}
