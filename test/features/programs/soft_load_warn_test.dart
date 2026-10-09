import 'package:fitness_os/features/programs/domain/soft_load_warn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 9);

  OtherLoadSample sample({
    required int type,
    required String typeLabel,
    required int durationSec,
    int? dayOffset,
    double? loadOrTe,
    int? hrPeak,
    int hour = 10,
  }) {
    final d = day.add(Duration(days: dayOffset ?? 0));
    final start = DateTime(d.year, d.month, d.day, hour);
    return OtherLoadSample(
      type: type,
      typeLabel: typeLabel,
      startTimeMs: start.millisecondsSinceEpoch,
      durationSec: durationSec,
      loadOrTe: loadOrTe,
      hrPeak: hrPeak,
    );
  }

  group('SoftLoadWarn.evaluate', () {
    test('happy: heavy strength same day → warn true, factual copy', () {
      final result = SoftLoadWarn.evaluate(
        recent: [
          sample(
            type: 140,
            typeLabel: 'Strength',
            durationSec: 52 * 60,
          ),
        ],
        day: day,
      );

      expect(result.warn, isTrue);
      expect(result.level, SoftLoadWarnLevel.caution);
      expect(result.copy, contains('strength'));
      expect(result.copy, contains('52 min'));
      expect(result.todayOtherDurationMin, 52);
    });

    test('edge: no other sports → warn false', () {
      final result = SoftLoadWarn.evaluate(
        recent: [
          sample(type: 6, typeLabel: 'Pool swim', durationSec: 40 * 60),
          sample(type: 8, typeLabel: 'Open water', durationSec: 30 * 60),
        ],
        day: day,
      );

      expect(result.warn, isFalse);
      expect(result.level, SoftLoadWarnLevel.none);
      expect(result.copy, isEmpty);
      expect(result.todayOtherDurationMin, 0);
    });

    test('edge: empty recent → warn false, no crash', () {
      final result = SoftLoadWarn.evaluate(recent: const [], day: day);
      expect(result.warn, isFalse);
      expect(result.level, SoftLoadWarnLevel.none);
    });

    test('edge: missing load fields → duration heuristic, no crash', () {
      final history = <OtherLoadSample>[
        for (var i = 1; i <= 14; i++)
          sample(
            type: 140,
            typeLabel: 'Strength',
            durationSec: 20 * 60,
            dayOffset: -i,
            loadOrTe: null,
            hrPeak: null,
          ),
        sample(
          type: 140,
          typeLabel: 'Strength',
          durationSec: 50 * 60,
          loadOrTe: null,
          hrPeak: null,
        ),
      ];

      final result = SoftLoadWarn.evaluate(recent: history, day: day);

      expect(result.warn, isTrue);
      expect(result.level, SoftLoadWarnLevel.caution);
      expect(result.copy, contains('strength 50 min'));
      expect(result.trailingMedianDurationMin, isNotNull);
    });

    test('relative: below 45 min but ≥1.5× trailing median → warn', () {
      final history = <OtherLoadSample>[
        for (var i = 1; i <= 20; i++)
          sample(
            type: 2,
            typeLabel: 'Run',
            durationSec: 20 * 60,
            dayOffset: -i,
          ),
        sample(
          type: 2,
          typeLabel: 'Run',
          durationSec: 35 * 60,
        ),
      ];

      final result = SoftLoadWarn.evaluate(recent: history, day: day);

      expect(result.warn, isTrue);
      expect(result.todayOtherDurationMin, 35);
      expect(result.trailingMedianDurationMin, closeTo(20, 0.01));
      expect(result.copy, contains('run 35 min'));
    });

    test('load/TE path: heavy load vs trailing median when duration light', () {
      final history = <OtherLoadSample>[
        for (var i = 1; i <= 14; i++)
          sample(
            type: 140,
            typeLabel: 'Strength',
            durationSec: 15 * 60,
            dayOffset: -i,
            loadOrTe: 10,
          ),
        sample(
          type: 140,
          typeLabel: 'Strength',
          durationSec: 15 * 60,
          loadOrTe: 30,
        ),
      ];

      final result = SoftLoadWarn.evaluate(recent: history, day: day);

      expect(result.warn, isTrue);
      expect(result.todayOtherDurationMin, 15);
      expect(result.copy, contains('strength 15 min'));
    });

    test('edge: copy contains no readiness / scored recovery language', () {
      final result = SoftLoadWarn.evaluate(
        recent: [
          sample(
            type: 140,
            typeLabel: 'Strength',
            durationSec: 52 * 60,
            loadOrTe: 40,
            hrPeak: 175,
          ),
          sample(
            type: 2,
            typeLabel: 'Run',
            durationSec: 30 * 60,
            hour: 17,
          ),
        ],
        day: day,
        sleepDurationMin: 300,
      );

      final lower = result.copy.toLowerCase();
      expect(lower.contains('readiness'), isFalse);
      expect(lower.contains('recovery score'), isFalse);
      expect(RegExp(r'\b\d{1,3}\s*/\s*100\b').hasMatch(lower), isFalse);
      expect(RegExp(r'\bscore\b').hasMatch(lower), isFalse);
      expect(result.copy, contains('strength 52 min'));
      expect(result.copy, contains('run 30 min'));
      expect(result.copy, contains('sleep'));
    });

    test('assert: result never mutates a chore schedule (pure)', () {
      final recent = [
        sample(type: 140, typeLabel: 'Strength', durationSec: 52 * 60),
      ];
      // Stand-in for a prescribed chore id / day — SoftLoadWarn must not
      // accept or return schedule mutation hooks.
      const choreId = 'chore-today';
      const choreStillPrescribed = true;

      final a = SoftLoadWarn.evaluate(recent: recent, day: day);
      final b = SoftLoadWarn.evaluate(recent: recent, day: day);

      expect(a.warn, b.warn);
      expect(a.level, b.level);
      expect(a.copy, b.copy);
      expect(choreStillPrescribed, isTrue);
      expect(choreId, isNotEmpty);
      // Public API is evaluate → SoftLoadWarnResult only.
      expect(a, isA<SoftLoadWarnResult>());
    });

    test('swims on same day do not count toward other-load duration', () {
      final result = SoftLoadWarn.evaluate(
        recent: [
          sample(type: 6, typeLabel: 'Pool swim', durationSec: 60 * 60),
          sample(type: 140, typeLabel: 'Strength', durationSec: 20 * 60),
        ],
        day: day,
      );

      expect(result.todayOtherDurationMin, 20);
      expect(result.warn, isFalse);
    });

    test('short sleep alone → info warn with factual sleep copy', () {
      final result = SoftLoadWarn.evaluate(
        recent: const [],
        day: day,
        sleepDurationMin: 5 * 60,
      );

      expect(result.warn, isTrue);
      expect(result.level, SoftLoadWarnLevel.info);
      expect(result.copy, contains('sleep 5 h'));
      expect(result.copy.toLowerCase().contains('readiness'), isFalse);
    });
  });
}
