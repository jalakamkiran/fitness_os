import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutChannelPeel', () {
    test('peels leftover/data/pace bodies and stamps lean honesty', () {
      final peeled = WorkoutChannelPeel.peel({
        'number': 7,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'dataCount': 2,
        'paceCount': 1,
        'observedType': 2,
        'leftoverBodies': [
          {'id': 0x66, 'len': 2, 'bodyBase64': 'qqo='},
        ],
        'dataPages': [
          {
            'index': 0,
            'leftoverBodies': [
              {'id': 0x7a, 'len': 1, 'bodyBase64': 'AQ=='},
            ],
          },
          {
            'index': 1,
            'leftoverBodies': [
              {'id': 0x7b, 'len': 1, 'bodyBase64': 'Ag=='},
            ],
          },
        ],
        'paceBlocks': [
          {
            'index': 0,
            'leftoverBodies': [
              {'id': 0x7c, 'len': 1, 'bodyBase64': 'Aw=='},
            ],
          },
        ],
      });

      expect(peeled.workoutNumber, 7);
      expect(peeled.observedType, 2);
      expect(peeled.totalsLeftovers, hasLength(1));
      expect(peeled.totalsLeftovers.single.bodyBase64, 'qqo=');
      expect(peeled.dataPages, hasLength(2));
      expect(peeled.paceBlocks, hasLength(1));
      expect(peeled.leftoversStatus, WorkoutStreamHonesty.present);
      expect(peeled.dataPagesStatus, WorkoutStreamHonesty.present);
      expect(peeled.paceBlocksStatus, WorkoutStreamHonesty.present);

      final lean = WorkoutChannelPeel.leanSummary({
        'number': 7,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'dataCount': 2,
        'paceCount': 1,
        'observedType': 2,
        'leftoverBodies': [
          {'id': 0x66, 'len': 2, 'bodyBase64': 'qqo='},
        ],
        'dataPages': [
          {
            'index': 0,
            'leftoverBodies': [
              {'id': 0x7a, 'len': 1, 'bodyBase64': 'AQ=='},
            ],
          },
        ],
      }, peeled);

      final json = lean.toJson();
      expect(json.containsKey('leftoverBodies'), isFalse);
      expect(json.containsKey('dataPages'), isFalse);
      expect(json.containsKey('paceBlocks'), isFalse);
      expect(json.containsKey('bodyBase64'), isFalse);
      expect(json['leftoversStatus'], WorkoutStreamHonesty.present);
      expect(json['leftoverRefs'], [
        {'id': 0x66, 'len': 2},
      ]);
      expect(lean.observedType, 2);
    });

    test('Count=0 stamps streams unobserved and peels no empty series', () {
      final peeled = WorkoutChannelPeel.peel({
        'number': 8,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'dataCount': 0,
        'paceCount': 0,
      });
      expect(peeled.dataPages, isEmpty);
      expect(peeled.paceBlocks, isEmpty);
      expect(peeled.totalsLeftovers, isEmpty);
      expect(peeled.dataPagesStatus, WorkoutStreamHonesty.unobserved);
      expect(peeled.paceBlocksStatus, WorkoutStreamHonesty.unobserved);
      expect(peeled.leftoversStatus, WorkoutStreamHonesty.unobserved);
      expect(peeled.hasBodiesToPersist, isFalse);
    });

    test('partial pages stamp partial and keep arrived bodies', () {
      final peeled = WorkoutChannelPeel.peel({
        'number': 9,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'dataCount': 3,
        'paceCount': 2,
        'dataPages': [
          {
            'index': 0,
            'leftoverBodies': [
              {'id': 0x7a, 'len': 1, 'bodyBase64': 'AQ=='},
            ],
          },
        ],
        'paceBlocks': [
          {
            'index': 0,
            'leftoverBodies': [
              {'id': 0x7c, 'len': 1, 'bodyBase64': 'Aw=='},
            ],
          },
        ],
      });
      expect(peeled.dataPages, hasLength(1));
      expect(peeled.paceBlocks, hasLength(1));
      expect(peeled.dataPagesStatus, WorkoutStreamHonesty.partial);
      expect(peeled.paceBlocksStatus, WorkoutStreamHonesty.partial);
    });

    test('Count>0 with zero arrived pages stamps partial not unobserved', () {
      final peeled = WorkoutChannelPeel.peel({
        'number': 10,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'dataCount': 2,
        'paceCount': 1,
      });
      expect(peeled.dataPages, isEmpty);
      expect(peeled.paceBlocks, isEmpty);
      expect(peeled.dataPagesStatus, WorkoutStreamHonesty.partial);
      expect(peeled.paceBlocksStatus, WorkoutStreamHonesty.partial);
    });
  });

  group('RunSessionStore', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('fos_run_session_');
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('happy: writes binary side-files and reloads after restart', () async {
      final store = RunSessionStore(rootOverride: () => tmp);
      final peeled = WorkoutChannelPeel.peel({
        'number': 42,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'dataCount': 1,
        'paceCount': 1,
        'leftoverBodies': [
          {'id': 0x66, 'len': 2, 'bodyBase64': 'qqo='},
        ],
        'dataPages': [
          {
            'index': 0,
            'leftoverBodies': [
              {'id': 0x7a, 'len': 1, 'bodyBase64': 'AQ=='},
            ],
          },
        ],
        'paceBlocks': [
          {
            'index': 0,
            'leftoverBodies': [
              {'id': 0x7c, 'len': 1, 'bodyBase64': 'Aw=='},
            ],
          },
        ],
      });

      await store.save(peeled);

      final leftoversDir =
          Directory('${tmp.path}/${GateAPrefs.workoutTotalsLeftoversDir}/42');
      final dataDir =
          Directory('${tmp.path}/${GateAPrefs.workoutDataPagesDir}/42');
      final paceDir =
          Directory('${tmp.path}/${GateAPrefs.workoutPaceBlocksDir}/42');
      expect(await leftoversDir.exists(), isTrue);
      expect(await dataDir.exists(), isTrue);
      expect(await paceDir.exists(), isTrue);

      final bin = File('${leftoversDir.path}/0.bin');
      expect(await bin.exists(), isTrue);
      expect(await bin.readAsBytes(), base64Decode('qqo='));

      // Simulate restart with a fresh store instance on the same root.
      final reloaded = RunSessionStore(rootOverride: () => tmp);
      final leftovers = await reloaded.loadTotalsLeftovers(42);
      expect(leftovers, hasLength(1));
      expect(leftovers.single.id, 0x66);
      expect(leftovers.single.bodyBase64, 'qqo=');

      final pages = await reloaded.loadDataPages(42);
      expect(pages, hasLength(1));
      expect(pages.single.index, 0);
      expect(pages.single.bodies.single.bodyBase64, 'AQ==');

      final pace = await reloaded.loadPaceBlocks(42);
      expect(pace, hasLength(1));
      expect(pace.single.bodies.single.bodyBase64, 'Aw==');
    });

    test('Count=0 / unobserved writes no zero series files', () async {
      final store = RunSessionStore(rootOverride: () => tmp);
      final peeled = WorkoutChannelPeel.peel({
        'number': 43,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'dataCount': 0,
        'paceCount': 0,
      });
      await store.save(peeled);
      expect(
        await Directory('${tmp.path}/${GateAPrefs.workoutDataPagesDir}/43')
            .exists(),
        isFalse,
      );
      expect(
        await Directory('${tmp.path}/${GateAPrefs.workoutPaceBlocksDir}/43')
            .exists(),
        isFalse,
      );
      expect(
        await Directory('${tmp.path}/${GateAPrefs.workoutTotalsLeftoversDir}/43')
            .exists(),
        isFalse,
      );
    });

    test('partial pages persist arrived bodies only', () async {
      final store = RunSessionStore(rootOverride: () => tmp);
      final peeled = WorkoutChannelPeel.peel({
        'number': 44,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'dataCount': 3,
        'dataPages': [
          {
            'index': 1,
            'leftoverBodies': [
              {'id': 0x7a, 'len': 1, 'bodyBase64': 'AQ=='},
            ],
          },
        ],
      });
      expect(peeled.dataPagesStatus, WorkoutStreamHonesty.partial);
      await store.save(peeled);
      final pages = await store.loadDataPages(44);
      expect(pages, hasLength(1));
      expect(pages.single.index, 1);
    });

    test('clearLocal empties leftovers/data/pace dirs', () async {
      final store = RunSessionStore(rootOverride: () => tmp);
      final peeled = WorkoutChannelPeel.peel({
        'number': 45,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'dataCount': 1,
        'paceCount': 1,
        'leftoverBodies': [
          {'id': 0x66, 'len': 2, 'bodyBase64': 'qqo='},
        ],
        'dataPages': [
          {
            'index': 0,
            'leftoverBodies': [
              {'id': 0x7a, 'len': 1, 'bodyBase64': 'AQ=='},
            ],
          },
        ],
        'paceBlocks': [
          {
            'index': 0,
            'leftoverBodies': [
              {'id': 0x7c, 'len': 1, 'bodyBase64': 'Aw=='},
            ],
          },
        ],
      });
      await store.save(peeled);
      await store.clearLocal();

      for (final rel in [
        GateAPrefs.workoutTotalsLeftoversDir,
        GateAPrefs.workoutDataPagesDir,
        GateAPrefs.workoutPaceBlocksDir,
      ]) {
        final dir = Directory('${tmp.path}/$rel');
        expect(await dir.exists(), isFalse);
      }
    });
  });
}
