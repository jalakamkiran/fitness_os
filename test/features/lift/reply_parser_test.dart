import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:fitness_os/features/lift/domain/reply_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const plan = PlannedSet(
    exerciseId: 'bench',
    name: 'Bench',
    setIndex: 1,
    globalIndex: 1,
    plannedKg: 60,
    plannedReps: 8,
    restSec: 120,
  );

  test('done variants keep plan', () {
    for (final raw in ['Done', 'done as planned', 'OK', 'Yes']) {
      final o = parseReply(raw, plan);
      expect(o.actualKg, 60);
      expect(o.actualReps, 8);
      expect(o.failed, isFalse);
    }
  });

  test('rep and kg deltas', () {
    expect(parseReply('-1 rep', plan).actualReps, 7);
    expect(parseReply('+2.5 kg', plan).actualKg, 62.5);
    expect(parseReply('Failed', plan).actualReps, 0);
    expect(parseReply('Failed', plan).failed, isTrue);
  });

  test('unknown keeps plan with flag', () {
    final o = parseReply('maybe later', plan);
    expect(o.unknownReply, isTrue);
    expect(o.actualReps, 8);
  });
}