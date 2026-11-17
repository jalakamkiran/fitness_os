import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:fitness_os/features/lift/domain/session_runner.dart';
import 'package:flutter_test/flutter_test.dart';

PlannedSession _twoByTwo() {
  return PlannedSession(
    sessionId: 'ps_test',
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
      PlannedExercise(
        exerciseId: 'b',
        name: 'B',
        sets: 2,
        targetKg: 40,
        targetReps: 6,
        restSec: 90,
      ),
    ],
  );
}

void main() {
  test('happy path advances through four sets', () {
    final session = _twoByTwo();
    final runner = SessionRunner(session: session, plannedSets: session.expand());
    runner.start();
    expect(runner.state.phase, LiftRunnerPhase.notifying);
    runner.onNotified(1000);
    final s1 = runner.onReply(key: 'lift:ps_test:1', text: 'Done', rxAtMs: 2000);
    expect(s1, isNotNull);
    expect(runner.state.phase, LiftRunnerPhase.resting);
    var clock = 3000;
    final runner2 = SessionRunner(
      session: session,
      plannedSets: session.expand(),
      clock: () => clock,
    );
    runner2.start();
    runner2.onNotified(0);
    runner2.onReply(key: 'lift:ps_test:1', text: 'Done', rxAtMs: 1000);
    clock = 4000;
    runner2.tick();
    expect(runner2.state.currentIndex, 1);
    expect(runner2.state.phase, LiftRunnerPhase.notifying);
  });

  test('duplicate reply within 5s ignored', () {
    final session = _twoByTwo();
    final runner = SessionRunner(
      session: session,
      plannedSets: session.expand(),
      clock: () => 10_000,
    );
    runner.start();
    runner.onNotified(0);
    runner.onReply(key: 'lift:ps_test:1', text: 'Done', rxAtMs: 1000);
    expect(runner.onReply(key: 'lift:ps_test:1', text: 'Done', rxAtMs: 1500), isNull);
  });

  test('skip does not fabricate sets', () {
    final session = _twoByTwo();
    final runner = SessionRunner(session: session, plannedSets: session.expand());
    runner.start();
    runner.skipCurrent();
    expect(runner.state.currentIndex, 1);
  });
}