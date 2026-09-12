import 'dart:io';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/workout_leftover_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkoutLeftoverStore', () {
    late Directory tempRoot;
    late WorkoutLeftoverStore store;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('fos_leftover_');
      store = WorkoutLeftoverStore(rootOverride: () => tempRoot);
    });

    tearDown(() async {
      try {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('Happy path: save → file exists → reload bytes', () async {
      final bytes = List.generate(64, (i) => i % 256);
      final rel = await store.save(
        workoutNumber: 42,
        startTime: 1_700_000_000,
        bytes: bytes,
      );

      expect(
        rel,
        '${GateAPrefs.workoutLeftoversDir}/42_1700000000.bin',
      );
      final file = File('${tempRoot.path}/$rel');
      expect(await file.exists(), isTrue);
      expect(await file.length(), 64);

      final loaded = await store.load(
        workoutNumber: 42,
        startTime: 1_700_000_000,
      );
      expect(loaded, bytes);
    });

    test('Save integrity: temp → rename; no .tmp left', () async {
      final rel = await store.save(
        workoutNumber: 7,
        startTime: 100,
        bytes: List.generate(16, (i) => i),
      );
      expect(await File('${tempRoot.path}/$rel.tmp').exists(), isFalse);
      expect(await File('${tempRoot.path}/$rel').exists(), isTrue);
    });

    test('Missing file loads as null (unobserved, not zero)', () async {
      final loaded = await store.load(
        workoutNumber: 99,
        startTime: 1,
      );
      expect(loaded, isNull);
    });

    test('Present index path + missing file → null', () async {
      final rel = WorkoutLeftoverStore.relativePathFor(
        workoutNumber: 5,
        startTime: 50,
      );
      final loaded = await store.loadAtRelativePath(rel);
      expect(loaded, isNull);
    });

    test('Rejects absolute / escape paths', () async {
      expect(await store.loadAtRelativePath('/tmp/evil.bin'), isNull);
      expect(
        await store.loadAtRelativePath(
          '${GateAPrefs.workoutLeftoversDir}/../evil.bin',
        ),
        isNull,
      );
      expect(
        await store.loadAtRelativePath('workouts/hr_samples/x.bin'),
        isNull,
      );
    });

    test('Rejects symlink that escapes leftover root', () async {
      final leftovers =
          Directory('${tempRoot.path}/${GateAPrefs.workoutLeftoversDir}');
      await leftovers.create(recursive: true);
      final outside = File('${tempRoot.path}/outside_secret.bin');
      await outside.writeAsBytes([7, 7, 7, 7]);
      final linkPath = '${leftovers.path}/escape.bin';
      try {
        await Link(linkPath).create(outside.path);
      } on PathAccessException {
        // Some CI sandboxes disallow symlinks — skip assertion.
        return;
      } on FileSystemException {
        return;
      }

      final loaded = await store.loadAtRelativePath(
        '${GateAPrefs.workoutLeftoversDir}/escape.bin',
      );
      expect(loaded, isNull);
    });

    test('clearLocal empties leftover dir', () async {
      await store.save(
        workoutNumber: 1,
        startTime: 10,
        bytes: List.generate(8, (i) => i),
      );
      await store.save(
        workoutNumber: 2,
        startTime: 20,
        bytes: List.generate(8, (i) => i),
      );

      await store.clearLocal();

      final dir =
          Directory('${tempRoot.path}/${GateAPrefs.workoutLeftoversDir}');
      expect(await dir.exists(), isFalse);
      expect(
        await store.load(workoutNumber: 1, startTime: 10),
        isNull,
      );
    });

    test('Overwrite same identity replaces bytes', () async {
      await store.save(
        workoutNumber: 3,
        startTime: 30,
        bytes: [1, 2, 3],
      );
      await store.save(
        workoutNumber: 3,
        startTime: 30,
        bytes: [9, 8, 7, 6],
      );
      final loaded = await store.load(workoutNumber: 3, startTime: 30);
      expect(loaded, [9, 8, 7, 6]);
    });
  });
}
