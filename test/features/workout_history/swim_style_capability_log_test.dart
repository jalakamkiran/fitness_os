import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/swim_style_capability_log.dart';

void main() {
  group('classifySwimStyleCapability', () {
    test('styles present → per-lap lines + styles_logged (AE1)', () {
      const workout = WorkoutSummary(
        number: 42,
        startTime: 1_700_000_100,
        endTime: 1_700_000_400,
        durationSec: 300,
        type: 6,
        segmentsCount: 3,
        segments: [
          WorkoutSegment(index: 0, style: 2),
          WorkoutSegment(index: 1, style: 4),
          WorkoutSegment(index: 2, style: 1),
        ],
      );

      final outcome = classifySwimStyleCapability(workout);
      expect(outcome, isNotNull);
      expect(outcome!.status, SwimStyleCapabilityStatus.stylesLogged);
      expect(outcome.reason, isNull);
      expect(outcome.laps, hasLength(3));
      expect(outcome.laps.map((l) => l.styleCode).toList(), [2, 4, 1]);
      expect(outcome.laps.map((l) => l.label).toList(), [
        'Freestyle',
        'Backstroke',
        'Breaststroke',
      ]);

      final lines = outcome.toLogLines();
      expect(lines, hasLength(4));
      expect(
        lines[0],
        'swim-style number=42 startTime=1700000100 lap=0 style=2 label=Freestyle',
      );
      expect(
        lines[1],
        'swim-style number=42 startTime=1700000100 lap=1 style=4 label=Backstroke',
      );
      expect(
        lines[2],
        'swim-style number=42 startTime=1700000100 lap=2 style=1 label=Breaststroke',
      );
      expect(
        lines[3],
        'swim-style-outcome number=42 startTime=1700000100 '
        'status=styles_logged laps=3',
      );
    });

    test('segmentsCount == 0 → blocked segments_count_zero (AE2)', () {
      const workout = WorkoutSummary(
        number: 7,
        startTime: 100,
        endTime: 200,
        durationSec: 100,
        type: 6,
        segmentsCount: 0,
        segments: [],
      );

      final outcome = classifySwimStyleCapability(workout)!;
      expect(outcome.status, SwimStyleCapabilityStatus.blocked);
      expect(outcome.reason, 'segments_count_zero');
      expect(outcome.laps, isEmpty);
      expect(
        outcome.toLogLines().single,
        'swim-style-outcome number=7 startTime=100 '
        'status=blocked reason=segments_count_zero',
      );
    });

    test('empty segments → blocked segments_empty', () {
      const workout = WorkoutSummary(
        number: 8,
        startTime: 200,
        endTime: 300,
        durationSec: 100,
        type: 6,
        segments: [],
      );

      final outcome = classifySwimStyleCapability(workout)!;
      expect(outcome.status, SwimStyleCapabilityStatus.blocked);
      expect(outcome.reason, 'segments_empty');
      expect(outcome.laps, isEmpty);
    });

    test('segments present but all style null → all_styles_null', () {
      const workout = WorkoutSummary(
        number: 9,
        startTime: 300,
        endTime: 400,
        durationSec: 100,
        type: 6,
        segmentsCount: 2,
        segments: [
          WorkoutSegment(index: 0),
          WorkoutSegment(index: 1),
        ],
      );

      final outcome = classifySwimStyleCapability(workout)!;
      expect(outcome.status, SwimStyleCapabilityStatus.blocked);
      expect(outcome.reason, 'all_styles_null');
      expect(outcome.laps, hasLength(2));
      expect(outcome.laps.every((l) => l.styleCode == null), isTrue);
      expect(outcome.toLogLines().last, contains('reason=all_styles_null'));
      expect(outcome.toLogLines().first, contains('style=null label=null'));
    });

    test('unknown style code appears raw in log line', () {
      const workout = WorkoutSummary(
        number: 10,
        startTime: 400,
        endTime: 500,
        durationSec: 100,
        type: 6,
        segments: [WorkoutSegment(index: 0, style: 99)],
      );

      final outcome = classifySwimStyleCapability(workout)!;
      expect(outcome.status, SwimStyleCapabilityStatus.stylesLogged);
      expect(outcome.laps.single.label, 'Stroke 99');
      expect(outcome.toLogLines().first, contains('style=99 label=Stroke 99'));
    });

    test('non-swim workout → null (no capability claim)', () {
      const workout = WorkoutSummary(
        number: 1,
        startTime: 100,
        endTime: 200,
        durationSec: 100,
        type: 2,
      );
      expect(classifySwimStyleCapability(workout), isNull);
    });

    test('partial null styles still styles_logged', () {
      const workout = WorkoutSummary(
        number: 11,
        startTime: 500,
        endTime: 600,
        durationSec: 100,
        type: 6,
        segments: [
          WorkoutSegment(index: 0, style: 2),
          WorkoutSegment(index: 1),
          WorkoutSegment(index: 2, style: 4),
        ],
      );

      final outcome = classifySwimStyleCapability(workout)!;
      expect(outcome.status, SwimStyleCapabilityStatus.stylesLogged);
      expect(outcome.laps, hasLength(3));
    });
  });

  group('syncNotOkSwimStyleOutcomeLine', () {
    test('formats sync failure distinctly from capability blocked', () {
      expect(
        syncNotOkSwimStyleOutcomeLine(WorkoutSyncStatus.partialBatch),
        'swim-style-outcome status=sync_not_ok syncStatus=partial_batch',
      );
      expect(
        syncNotOkSwimStyleOutcomeLine(WorkoutSyncStatus.busy),
        'swim-style-outcome status=sync_not_ok syncStatus=busy',
      );
    });
  });
}
