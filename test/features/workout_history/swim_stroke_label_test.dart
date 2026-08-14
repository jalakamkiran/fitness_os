import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_os/features/workout_history/domain/swim_stroke_label.dart';

void main() {
  group('swimStrokeLabel', () {
    test('maps known codes 1–5', () {
      expect(swimStrokeLabel(1), 'Breaststroke');
      expect(swimStrokeLabel(2), 'Freestyle');
      expect(swimStrokeLabel(3), 'Butterfly');
      expect(swimStrokeLabel(4), 'Backstroke');
      expect(swimStrokeLabel(5), 'Medley');
    });

    test('null returns stable non-empty raw label', () {
      expect(swimStrokeLabel(null), 'null');
      expect(swimStrokeLabel(null), isNotEmpty);
    });

    test('unknown codes include raw numeric', () {
      expect(swimStrokeLabel(0), 'Stroke 0');
      expect(swimStrokeLabel(6), 'Stroke 6');
      expect(swimStrokeLabel(99), contains('99'));
    });
  });
}
