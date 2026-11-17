import 'dart:io';

import 'package:fitness_os/features/lift/data/lift_store.dart';
import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:fitness_os/features/lift/domain/strength_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late LiftStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lift_store_test');
    store = LiftStore(rootOverride: () => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('atomic write and reload strength sets', () async {
    final set = StrengthSet(
      id: 'ps_a_bench_1',
      sessionId: 'ps',
      exerciseId: 'bench',
      exercise: 'Bench',
      setIndex: 1,
      plannedKg: 60,
      plannedReps: 8,
      actualKg: 60,
      actualReps: 8,
      failed: false,
      notifiedAtMs: 1,
      loggedAtMs: 2,
      source: 'watch_reply',
    );
    await store.upsertStrengthSet(set);
    final loaded = await store.loadStrengthSets();
    expect(loaded.single.id, set.id);
    final pending = await store.loadPendingUploadIds();
    expect(pending, contains(set.id));
  });

  test('planned sessions round trip', () async {
    final session = PlannedSession(
      sessionId: 'ps1',
      title: 'Leg',
      plannedFor: DateTime.utc(2026, 1, 2),
      source: 'manual',
      exercises: const [],
    );
    await store.savePlannedSessions([session]);
    final out = await store.loadPlannedSessions();
    expect(out.single.sessionId, 'ps1');
  });
}