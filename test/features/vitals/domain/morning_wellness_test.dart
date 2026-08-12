import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/vitals/domain/morning_wellness.dart';

void main() {
  group('MorningWellness', () {
    test('complete map round-trips', () {
      final original = MorningWellness(
        sleepQuality: 3,
        fatigue: 4,
        soreness: 5,
        stress: 2,
        answeredAt: DateTime.utc(2026, 8, 13, 6, 30),
      );
      expect(original.isComplete, isTrue);
      final parsed = MorningWellness.tryParse(original.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.sleepQuality, 3);
      expect(parsed.fatigue, 4);
      expect(parsed.soreness, 5);
      expect(parsed.stress, 2);
      expect(parsed.schema, MorningWellness.schemaVersion);
      expect(parsed.answeredAt?.toUtc(), DateTime.utc(2026, 8, 13, 6, 30));
    });

    test('legacy string is incomplete', () {
      expect(MorningWellness.tryParse('good'), isNull);
      expect(MorningWellness.isCompleteRaw('good'), isFalse);
    });

    test('map missing soreness is incomplete', () {
      expect(
        MorningWellness.tryParse({
          'sleepQuality': 3,
          'fatigue': 4,
          'stress': 2,
        }),
        isNull,
      );
    });

    test('out of range ints are incomplete', () {
      expect(
        MorningWellness.tryParse({
          'sleepQuality': 0,
          'fatigue': 4,
          'soreness': 5,
          'stress': 2,
        }),
        isNull,
      );
      expect(
        MorningWellness.tryParse({
          'sleepQuality': 3,
          'fatigue': 8,
          'soreness': 5,
          'stress': 2,
        }),
        isNull,
      );
    });

    test('wrong-typed field is incomplete without throw', () {
      expect(
        MorningWellness.tryParse({
          'sleepQuality': '3',
          'fatigue': 4,
          'soreness': 5,
          'stress': 2,
        }),
        isNull,
      );
    });

    test('toString is redacted', () {
      const w = MorningWellness(
        sleepQuality: 7,
        fatigue: 7,
        soreness: 7,
        stress: 7,
      );
      expect(w.toString(), 'MorningWellness(isComplete: true)');
      expect(w.toString(), isNot(contains('7')));
    });
  });
}
