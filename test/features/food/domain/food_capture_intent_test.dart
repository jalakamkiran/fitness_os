import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/food/domain/food_capture_intent.dart';

void main() {
  setUp(() {
    FoodCaptureIntent.clearPending();
  });

  group('FoodCaptureIntent', () {
    test('hasPending returns false initially', () {
      expect(FoodCaptureIntent.hasPending(), false);
    });

    test('setPending stores intent', () {
      final intent = FoodCaptureIntent(slot: 'breakfast', localDay: '2026-09-06');
      FoodCaptureIntent.setPending(intent);

      expect(FoodCaptureIntent.hasPending(), true);
    });

    test('consumePending returns and clears intent', () {
      final intent = FoodCaptureIntent(slot: 'lunch', localDay: '2026-09-06');
      FoodCaptureIntent.setPending(intent);

      final consumed = FoodCaptureIntent.consumePending();

      expect(consumed, isNotNull);
      expect(consumed!.slot, 'lunch');
      expect(consumed.localDay, '2026-09-06');
      expect(FoodCaptureIntent.hasPending(), false);
    });

    test('setPending coalesces (overwrites previous)', () {
      final first = FoodCaptureIntent(slot: 'breakfast', localDay: '2026-09-06');
      final second = FoodCaptureIntent(slot: 'dinner', localDay: '2026-09-07');

      FoodCaptureIntent.setPending(first);
      FoodCaptureIntent.setPending(second);

      final consumed = FoodCaptureIntent.consumePending();
      expect(consumed!.slot, 'dinner');
      expect(consumed.localDay, '2026-09-07');
    });

    test('clearPending removes intent without consuming', () {
      final intent = FoodCaptureIntent(slot: 'snack', localDay: '2026-09-06');
      FoodCaptureIntent.setPending(intent);

      FoodCaptureIntent.clearPending();

      expect(FoodCaptureIntent.hasPending(), false);
      expect(FoodCaptureIntent.consumePending(), isNull);
    });
  });
}
