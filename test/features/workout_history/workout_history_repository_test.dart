import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/repositories/workout_history_repository_impl.dart';
import 'package:fitness_os/features/workout_history/data/workout_leftover_store.dart';

class _StubLink extends HuaweiLink {
  _StubLink({this.result});

  WorkoutSyncResult? result;
  int syncCalls = 0;
  int? lastStartUnix;

  @override
  Future<WorkoutSyncResult> syncWorkouts({
    required int startUnix,
    required int endUnix,
  }) async {
    syncCalls++;
    lastStartUnix = startUnix;
    return result ??
        const WorkoutSyncResult(
          status: WorkoutSyncStatus.empty,
          workouts: [],
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutHistoryRepositoryImpl', () {
    test('blocks sync when gate_a_passed is false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink();
      final repo = WorkoutHistoryRepositoryImpl(link: link, prefs: prefs);

      final out = await repo.syncFromWatch();
      expect(out, isA<Left>());
      expect(link.syncCalls, 0);
    });

    test('incremental sync uses cursor minus overlap when locals complete',
        () async {
      // Past cursor (must be < now so overlap clamp does not force endUnix).
      const cursor = 1_700_000_000;
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.lastSyncCursor: cursor,
        GateAPrefs.swimSegmentParserVersion:
            WorkoutHistoryRepositoryImpl.currentSwimSegmentParserVersion,
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 3,
              startTime: 1_700_000_100,
              endTime: 1_700_003_600,
              durationSec: 3500,
              type: 2,
              distanceM: 5000,
            ),
          ],
        ),
      );
      var settled = 0;
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        onSyncSettled: () => settled++,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final list = (out as Right).value;
      expect(list, hasLength(1));
      expect(list.first.type, 2);
      expect(link.syncCalls, 1);
      expect(
        link.lastStartUnix,
        cursor - WorkoutHistoryRepositoryImpl.cursorOverlapSec,
      );
      expect(prefs.getInt(GateAPrefs.lastSyncCursor), 1_700_003_601);
      expect(await repo.loadLocal(), hasLength(1));
      expect(settled, 1);
    });

    test('cold-start sync uses last N days when no cursor', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.empty,
          workouts: [],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(link: link, prefs: prefs);

      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await repo.syncFromWatch();
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final start = link.lastStartUnix!;
      final minExpected =
          before - WorkoutHistoryRepositoryImpl.coldStartWindowDays * 86400;
      final maxExpected =
          after - WorkoutHistoryRepositoryImpl.coldStartWindowDays * 86400;
      expect(start, greaterThanOrEqualTo(minExpected));
      expect(start, lessThanOrEqualTo(maxExpected));
    });

    test('partial local extends delta window to earliest partial', () async {
      const cursor = 1_700_000_000;
      const partialStart = 1_699_000_000;
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.lastSyncCursor: cursor,
        GateAPrefs.swimSegmentParserVersion:
            WorkoutHistoryRepositoryImpl.currentSwimSegmentParserVersion,
        GateAPrefs.workoutsJson:
            '[{"number":1,"startTime":$partialStart,"endTime":${partialStart + 100},'
                '"durationSec":100,"type":6,"enrichmentStatus":"partial"}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.empty,
          workouts: [],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(link: link, prefs: prefs);

      await repo.syncFromWatch();
      expect(
        link.lastStartUnix,
        partialStart - WorkoutHistoryRepositoryImpl.cursorOverlapSec,
      );
    });

    test('stale swim segment parser version still uses delta cursor window',
        () async {
      const cursor = 1_700_000_000;
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.lastSyncCursor: cursor,
        GateAPrefs.swimSegmentParserVersion: 1,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_swim_reparse_');
      addTearDown(() => tmp.delete(recursive: true));
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 12,
              startTime: 1_700_000_100,
              endTime: 1_700_003_600,
              durationSec: 3500,
              type: 6,
              distanceM: 475,
            ),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      expect(
        link.lastStartUnix,
        cursor - WorkoutHistoryRepositoryImpl.cursorOverlapSec,
      );
      expect(
        prefs.getInt(GateAPrefs.swimSegmentParserVersion),
        WorkoutHistoryRepositoryImpl.currentSwimSegmentParserVersion,
      );
    });

    test('after parser bump stamps, next sync uses incremental window',
        () async {
      const cursor = 1_700_000_000;
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.lastSyncCursor: cursor,
        // Stale vs current — still delta; no full-history force.
        GateAPrefs.swimSegmentParserVersion: 1,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_swim_bump_');
      addTearDown(() => tmp.delete(recursive: true));
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 20,
              startTime: 1_700_000_100,
              endTime: 1_700_003_600,
              durationSec: 3500,
              type: 6,
              distanceM: 500,
              segmentsCount: 0,
              segments: [],
            ),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        swimRootOverride: () => tmp,
      );

      final first = await repo.syncFromWatch();
      expect(first, isA<Right>());
      expect(
        link.lastStartUnix,
        cursor - WorkoutHistoryRepositoryImpl.cursorOverlapSec,
      );
      expect(
        prefs.getInt(GateAPrefs.swimSegmentParserVersion),
        WorkoutHistoryRepositoryImpl.currentSwimSegmentParserVersion,
      );

      link.result = const WorkoutSyncResult(
        status: WorkoutSyncStatus.empty,
        workouts: [],
      );
      await repo.syncFromWatch();
      expect(
        link.lastStartUnix,
        // Cursor advanced from first ok merge (endTime+1), then overlap.
        (1_700_003_600 + 1) - WorkoutHistoryRepositoryImpl.cursorOverlapSec,
      );
    });

    test('ok sync with swim styles does not change summary style fields',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_swim_style_');
      addTearDown(() => tmp.delete(recursive: true));

      const incoming = WorkoutSummary(
        number: 21,
        startTime: 1_700_000_000,
        endTime: 1_700_000_300,
        durationSec: 300,
        type: 6,
        distanceM: 75,
        segmentsCount: 3,
        segments: [
          WorkoutSegment(index: 0, style: 2, distanceM: 25),
          WorkoutSegment(index: 1, style: 4, distanceM: 25),
          WorkoutSegment(index: 2, style: 1, distanceM: 25),
        ],
      );
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [incoming],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local.single.segments!.map((s) => s.style).toList(), [2, 4, 1]);
      final swim = await repo.loadCanonicalSwim(21);
      expect(swim!.p0.laps.map((l) => l.style).toList(), [2, 4, 1]);
    });

    test('busy while activity in flight does not wipe workout list', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.workoutsJson:
            '[{"number":1,"startTime":100,"endTime":200,"durationSec":100,"type":1}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.busy,
          message: 'Another Sync is already in progress',
          workouts: [],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(link: link, prefs: prefs);

      final out = await repo.syncFromWatch();
      expect(out, isA<Left>());
      expect(await repo.loadLocal(), hasLength(1));
      expect(prefs.getString(GateAPrefs.workoutsJson), isNotNull);
    });

    test('ok sync persists canonical swim side-file for pool workout', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_swim_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 11,
              startTime: 1_700_000_000,
              endTime: 1_700_003_683,
              durationSec: 3683,
              type: 6,
              distanceM: 500,
              strokes: 350,
              avgSwolf: 165,
              poolLength: 2500,
              laps: 20,
              hrMin: 90,
              hrMax: 140,
              segments: [
                WorkoutSegment(
                  index: 0,
                  distanceM: 25,
                  durationSec: 11,
                  strokes: 124,
                  avgSwolf: 135,
                ),
              ],
            ),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final swim = await repo.loadCanonicalSwim(11);
      expect(swim, isNotNull);
      expect(swim!.poolLengthM, 25);
      expect(swim.p0.totalStrokes, 350);
      expect(swim.p0.lengthCoveragePartial, isTrue);
      expect(repo.canonicalSwimFromSummary((out as Right).value.first), isNotNull);
    });

    test('ok strength sync writes leftover side-file; prefs have len not body',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_leftover_ok_');
      addTearDown(() => tmp.delete(recursive: true));

      final leftoverBytes = Uint8List.fromList(List.generate(48, (i) => i + 1));
      final link = _StubLink(
        result: WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 1401,
              startTime: 1_700_100_000,
              endTime: 1_700_100_900,
              durationSec: 900,
              type: 140,
              calories: 220,
              hrMin: 88,
              hrMax: 152,
              load: 42,
              aerobicEffect: 3,
              recoveryTime: 720,
              trainingPoints: 15,
              leftoverBytes: leftoverBytes,
              leftoverLen: leftoverBytes.length,
              sampleFetch: 'none',
            ),
          ],
        ),
      );
      final leftoverStore = WorkoutLeftoverStore(rootOverride: () => tmp);
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        leftoverStore: leftoverStore,
        leftoverRootOverride: () => tmp,
        sideFileRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      expect(repo.lastLeftoverPersistLanded, isTrue);

      final rel = WorkoutLeftoverStore.relativePathFor(
        workoutNumber: 1401,
        startTime: 1_700_100_000,
      );
      expect(await File('${tmp.path}/$rel').exists(), isTrue);
      expect(await leftoverStore.loadAtRelativePath(rel), leftoverBytes);

      final prefsRaw = prefs.getString(GateAPrefs.workoutsJson)!;
      expect(prefsRaw.contains('"leftover"'), isFalse);
      expect(prefsRaw.contains(leftoverBytes.toString()), isFalse);
      final decoded = jsonDecode(prefsRaw) as List<dynamic>;
      final row = Map<String, dynamic>.from(decoded.single as Map);
      expect(row['leftoverLen'], 48);
      expect(row['leftoverPresent'], isTrue);
      expect(row['leftoverPath'], rel);
      expect(row.containsKey('leftover'), isFalse);
      expect(row['load'], 42);
      expect(row['aerobicEffect'], 3);
      expect(row['recoveryTime'], 720);
      expect(row['trainingPoints'], 15);
      expect(row.containsKey('anaerobicEffect'), isFalse);

      final local = await repo.loadLocal();
      expect(local.single.load, 42);
      expect(local.single.leftoverBytes, isNull);
      expect(local.single.leftoverPath, rel);
      expect(local.single.leftoverLen, 48);
    });

    test('ok sync attaches relative samplePath only; no HR series in prefs',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_sample_ref_');
      addTearDown(() => tmp.delete(recursive: true));

      final absoluteNative =
          '/data/user/0/com.example.fitness_os/files/'
          '${GateAPrefs.workoutHrSamplesDir}/1401_1700100000.bin';
      final link = _StubLink(
        result: WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary.fromMap({
              'number': 1402,
              'startTime': 1_700_100_000,
              'endTime': 1_700_100_600,
              'durationSec': 600,
              'type': 140,
              'sampleCount': 120,
              'sampleFetch': 'ok',
              'samplePath': absoluteNative,
            }),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        leftoverRootOverride: () => tmp,
        sideFileRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(
        local.single.samplePath,
        '${GateAPrefs.workoutHrSamplesDir}/1401_1700100000.bin',
      );
      expect(local.single.sampleFetch, 'ok');

      final prefsRaw = prefs.getString(GateAPrefs.workoutsJson)!;
      expect(prefsRaw.contains('/data/user'), isFalse);
      expect(prefsRaw.contains('hrSeries'), isFalse);
      expect(prefsRaw.contains('dataPages'), isFalse);
      final row = Map<String, dynamic>.from(
        (jsonDecode(prefsRaw) as List).single as Map,
      );
      expect(row['samplePath'], startsWith('${GateAPrefs.workoutHrSamplesDir}/'));
      expect(row.containsKey('leftover'), isFalse);
    });

    test('leftover write failure clears present and blocks leftover-keep land',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_leftover_fail_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 1403,
              startTime: 1_700_200_000,
              endTime: 1_700_200_300,
              durationSec: 300,
              type: 140,
              load: 10,
              leftoverBytes: Uint8List.fromList([1, 2, 3, 4]),
            ),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        leftoverStore: _FailingLeftoverStore(rootOverride: () => tmp),
        leftoverRootOverride: () => tmp,
        sideFileRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      expect(repo.lastLeftoverPersistLanded, isFalse);

      final local = await repo.loadLocal();
      expect(local.single.load, 10);
      expect(local.single.leftoverPresent, isFalse);
      expect(local.single.leftoverPath, isNull);
      expect(local.single.leftoverBytes, isNull);

      final prefsRaw = prefs.getString(GateAPrefs.workoutsJson)!;
      expect(prefsRaw.contains('"leftover"'), isFalse);
      final row = Map<String, dynamic>.from(
        (jsonDecode(prefsRaw) as List).single as Map,
      );
      expect(row['leftoverPresent'], isFalse);
      expect(row.containsKey('leftoverPath'), isFalse);
    });

    test('WorkoutSummary.toJson never embeds leftover bodies or HR series',
        () {
      final summary = WorkoutSummary(
        number: 9,
        startTime: 100,
        endTime: 200,
        durationSec: 100,
        type: 140,
        load: 7,
        leftoverBytes: Uint8List.fromList([9, 9, 9]),
        leftoverLen: 3,
        leftoverPresent: true,
        leftoverPath: '${GateAPrefs.workoutLeftoversDir}/9_100.bin',
        samplePath: '${GateAPrefs.workoutHrSamplesDir}/9_100.bin',
        sampleFetch: 'ok',
        sampleCount: 12,
      );
      final json = summary.toJson();
      expect(json.containsKey('leftover'), isFalse);
      expect(json.containsKey('leftoverBytes'), isFalse);
      expect(json.containsKey('dataPages'), isFalse);
      expect(json.containsKey('hrSeries'), isFalse);
      expect(json['leftoverLen'], 3);
      expect(json['leftoverPath'], endsWith('9_100.bin'));
      expect(json['samplePath'], endsWith('9_100.bin'));
      expect(json['load'], 7);

      final encoded = jsonEncode(json);
      expect(encoded.contains('[9, 9, 9]'), isFalse);
    });

    test('clearLocal wipes leftover and sample side-file dirs', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_clear_local_');
      addTearDown(() => tmp.delete(recursive: true));

      final leftoverStore = WorkoutLeftoverStore(rootOverride: () => tmp);
      await leftoverStore.save(
        workoutNumber: 1,
        startTime: 10,
        bytes: [1, 2, 3],
      );
      final sampleFile = File(
        '${tmp.path}/${GateAPrefs.workoutHrSamplesDir}/1_10.bin',
      );
      await sampleFile.parent.create(recursive: true);
      await sampleFile.writeAsBytes([4, 5, 6]);

      final repo = WorkoutHistoryRepositoryImpl(
        link: _StubLink(),
        prefs: prefs,
        leftoverStore: leftoverStore,
        sideFileRootOverride: () => tmp,
      );
      await repo.clearLocal();

      expect(
        await Directory('${tmp.path}/${GateAPrefs.workoutLeftoversDir}')
            .exists(),
        isFalse,
      );
      expect(
        await Directory('${tmp.path}/${GateAPrefs.workoutHrSamplesDir}')
            .exists(),
        isFalse,
      );
    });
  });
}

class _FailingLeftoverStore extends WorkoutLeftoverStore {
  _FailingLeftoverStore({super.rootOverride});

  @override
  Future<String> save({
    required int workoutNumber,
    required int startTime,
    required List<int> bytes,
  }) async {
    throw const FileSystemException('simulated leftover write failure');
  }
}
