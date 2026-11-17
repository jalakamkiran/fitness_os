import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expand flattens exercises', () {
    final session = PlannedSession(
      sessionId: 'ps1',
      title: 'T',
      plannedFor: DateTime.now(),
      source: 'debug',
      exercises: [
        PlannedExercise(
          exerciseId: 'a',
          name: 'A',
          sets: 2,
          targetKg: 50,
          targetReps: 5,
          restSec: 60,
        ),
      ],
    );
    final sets = session.expand();
    expect(sets.length, 2);
    expect(sets[0].globalIndex, 1);
    expect(sets[1].setIndex, 2);
    expect(sets[0].notificationKey('ps1'), 'lift:ps1:1');
  });

  test('json round trip', () {
    final session = PlannedSession(
      sessionId: 'ps1',
      title: 'T',
      plannedFor: DateTime.utc(2026, 3, 4),
      source: 'arjun',
      exercises: [
        PlannedExercise(
          exerciseId: 'sq',
          name: 'Squat',
          sets: 3,
          targetKg: 100,
          targetReps: 5,
          restSec: 180,
        ),
      ],
    );
    final back = PlannedSession.fromJson(session.toJson());
    expect(back.exercises.single.name, 'Squat');
  });
}