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

    test(
      'partial_batch persists Totals+leftover; sampleFetch stays timeout',
      () async {
        // AE6: sample timeout must not drop native Totals / leftovers.
        const cursor = 1_700_000_000;
        SharedPreferences.setMockInitialValues({
          GateAPrefs.gateAPassed: true,
          GateAPrefs.lastSyncCursor: cursor,
          GateAPrefs.swimSegmentParserVersion:
              WorkoutHistoryRepositoryImpl.currentSwimSegmentParserVersion,
          GateAPrefs.workoutsJson:
              '[{"number":1,"startTime":100,"endTime":200,"durationSec":100,"type":1}]',
        });
        final prefs = await SharedPreferences.getInstance();
        final tmp = await Directory.systemTemp.createTemp('fos_partial_batch_');
        addTearDown(() => tmp.delete(recursive: true));

        final leftoverBytes =
            Uint8List.fromList(List.generate(24, (i) => i + 10));
        final link = _StubLink(
          result: WorkoutSyncResult(
            status: WorkoutSyncStatus.partialBatch,
            message: 'Workout Sync incomplete — sample enrich timed out',
            workouts: [
              WorkoutSummary(
                number: 1408,
                startTime: 1_700_200_000,
                endTime: 1_700_200_900,
                durationSec: 900,
                type: 140,
                calories: 180,
                load: 33,
                dataCount: 2,
                enrichmentStatus: 'partial',
                sampleFetch: 'timeout',
                leftoverBytes: leftoverBytes,
                leftoverLen: leftoverBytes.length,
              ),
              // Totals-only historical must not keep enrichmentStatus=partial
              // (clock 3 must not reopen wide windows).
              const WorkoutSummary(
                number: 9,
                startTime: 1_650_000_000,
                endTime: 1_650_000_600,
                durationSec: 600,
                type: 140,
                calories: 50,
                enrichmentStatus: 'partial',
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
        final list = (out as Right).value;
        expect(list.map((w) => w.number), containsAll([1, 1408, 9]));

        final strength = list.firstWhere((w) => w.number == 1408);
        expect(strength.load, 33);
        expect(strength.calories, 180);
        expect(strength.sampleFetch, 'timeout');
        expect(strength.enrichmentStatus, 'partial');
        expect(strength.leftoverLen, 24);
        expect(strength.leftoverPath, isNotNull);

        final totalsOnly = list.firstWhere((w) => w.number == 9);
        expect(totalsOnly.enrichmentStatus, 'none');

        final rel = WorkoutLeftoverStore.relativePathFor(
          workoutNumber: 1408,
          startTime: 1_700_200_000,
        );
        expect(await File('${tmp.path}/$rel').exists(), isTrue);
        expect(await leftoverStore.loadAtRelativePath(rel), leftoverBytes);

        // Totals complete on partial_batch → cursor may advance.
        expect(prefs.getInt(GateAPrefs.lastSyncCursor), 1_700_200_901);
        // Pre-sync row 1 kept (Right replaces list with merge, not drop).
        expect(list.firstWhere((w) => w.number == 1).type, 1);
      },
    );

    test(
      'stuck with Totals prefix persists maps but does not advance cursor',
      () async {
        const cursor = 1_700_000_000;
        SharedPreferences.setMockInitialValues({
          GateAPrefs.gateAPassed: true,
          GateAPrefs.lastSyncCursor: cursor,
          GateAPrefs.swimSegmentParserVersion:
              WorkoutHistoryRepositoryImpl.currentSwimSegmentParserVersion,
        });
        final prefs = await SharedPreferences.getInstance();
        final tmp = await Directory.systemTemp.createTemp('fos_stuck_prefix_');
        addTearDown(() => tmp.delete(recursive: true));

        final leftoverBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
        final link = _StubLink(
          result: WorkoutSyncResult(
            status: WorkoutSyncStatus.stuck,
            message: 'Workout totals timed out at #42',
            workouts: [
              WorkoutSummary(
                number: 41,
                startTime: 1_700_300_000,
                endTime: 1_700_300_500,
                durationSec: 500,
                type: 140,
                calories: 90,
                load: 12,
                leftoverBytes: leftoverBytes,
                leftoverLen: leftoverBytes.length,
                sampleFetch: 'none',
                enrichmentStatus: 'none',
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
        final list = (out as Right).value;
        expect(list, hasLength(1));
        expect(list.single.number, 41);
        expect(list.single.load, 12);
        expect(list.single.leftoverLen, 8);

        final rel = WorkoutLeftoverStore.relativePathFor(
          workoutNumber: 41,
          startTime: 1_700_300_000,
        );
        expect(await File('${tmp.path}/$rel').exists(), isTrue);

        // Count-incomplete stuck must not advance past unfetched numbers.
        expect(prefs.getInt(GateAPrefs.lastSyncCursor), cursor);
      },
    );

    test('stuck with empty workouts does not merge; prior rows kept', () async {
      // AE7: empty Dart-abandon stuck stays blocked.
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.lastSyncCursor: 1_700_000_000,
        GateAPrefs.workoutsJson:
            '[{"number":7,"startTime":100,"endTime":200,"durationSec":100,"type":140,"load":9}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.stuck,
          message: 'Sync stuck — disconnect and reconnect',
          workouts: [],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(link: link, prefs: prefs);

      final out = await repo.syncFromWatch();
      expect(out, isA<Left>());
      final local = await repo.loadLocal();
      expect(local, hasLength(1));
      expect(local.single.number, 7);
      expect(local.single.load, 9);
      expect(prefs.getInt(GateAPrefs.lastSyncCursor), 1_700_000_000);
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

    // --- U7: presence-preserving merge (replaces replace-by-number contract) ---

    test(
        'Totals-only re-sync same number+startTime keeps leftover file and sample refs',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u7_keep_');
      addTearDown(() => tmp.delete(recursive: true));

      final leftoverBytes = Uint8List.fromList(List.generate(32, (i) => i + 7));
      final sampleRel =
          '${GateAPrefs.workoutHrSamplesDir}/1501_1700500000.bin';
      final sampleFile = File('${tmp.path}/$sampleRel');
      await sampleFile.parent.create(recursive: true);
      await sampleFile.writeAsBytes([1, 2, 3, 4, 5]);

      final link = _StubLink(
        result: WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 1501,
              startTime: 1_700_500_000,
              endTime: 1_700_500_900,
              durationSec: 900,
              type: 140,
              load: 42,
              leftoverBytes: leftoverBytes,
              leftoverLen: leftoverBytes.length,
              samplePath: sampleRel,
              sampleCount: 80,
              sampleFetch: 'ok',
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

      expect(await repo.syncFromWatch(), isA<Right>());
      final rel = WorkoutLeftoverStore.relativePathFor(
        workoutNumber: 1501,
        startTime: 1_700_500_000,
      );
      expect(await leftoverStore.loadAtRelativePath(rel), leftoverBytes);

      // Count-overlap Totals-only re-fetch: same identity, no leftover/samples.
      link.result = const WorkoutSyncResult(
        status: WorkoutSyncStatus.ok,
        workouts: [
          WorkoutSummary(
            number: 1501,
            startTime: 1_700_500_000,
            endTime: 1_700_500_900,
            durationSec: 900,
            type: 140,
            calories: 200,
            // load absent this pull — must leave prior 42
            sampleFetch: 'none',
          ),
        ],
      );
      expect(await repo.syncFromWatch(), isA<Right>());

      expect(await leftoverStore.loadAtRelativePath(rel), leftoverBytes);
      expect(await sampleFile.exists(), isTrue);

      final local = await repo.loadLocal();
      expect(local, hasLength(1));
      expect(local.single.load, 42);
      expect(local.single.calories, 200);
      expect(local.single.leftoverPresent, isTrue);
      expect(local.single.leftoverPath, rel);
      expect(local.single.leftoverLen, 32);
      expect(local.single.samplePath, sampleRel);
      expect(local.single.sampleCount, 80);
      expect(local.single.sampleFetch, 'ok');
    });

    test(
        'incoming more complete sample series replaces thinner local sample refs',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u7_richer_');
      addTearDown(() => tmp.delete(recursive: true));

      final thinRel =
          '${GateAPrefs.workoutHrSamplesDir}/1502_1700500100.bin';
      await File('${tmp.path}/$thinRel').parent.create(recursive: true);
      await File('${tmp.path}/$thinRel').writeAsBytes([9]);

      final link = _StubLink(
        result: WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 1502,
              startTime: 1_700_500_100,
              endTime: 1_700_500_400,
              durationSec: 300,
              type: 140,
              samplePath: thinRel,
              sampleCount: 10,
              sampleFetch: 'partial',
            ),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        leftoverRootOverride: () => tmp,
        sideFileRootOverride: () => tmp,
      );
      expect(await repo.syncFromWatch(), isA<Right>());

      final richRel =
          '${GateAPrefs.workoutHrSamplesDir}/1502_1700500100_full.bin';
      await File('${tmp.path}/$richRel').parent.create(recursive: true);
      await File('${tmp.path}/$richRel').writeAsBytes(List.filled(40, 1));

      link.result = WorkoutSyncResult(
        status: WorkoutSyncStatus.ok,
        workouts: [
          WorkoutSummary(
            number: 1502,
            startTime: 1_700_500_100,
            endTime: 1_700_500_400,
            durationSec: 300,
            type: 140,
            samplePath: richRel,
            sampleCount: 120,
            sampleFetch: 'ok',
          ),
        ],
      );
      expect(await repo.syncFromWatch(), isA<Right>());

      final local = await repo.loadLocal();
      expect(local.single.samplePath, richRel);
      expect(local.single.sampleCount, 120);
      expect(local.single.sampleFetch, 'ok');
    });

    test(
        'same number different startTime replaces leftover blobs — no glue',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u7_new_session_');
      addTearDown(() => tmp.delete(recursive: true));

      final oldBytes = Uint8List.fromList([1, 1, 1, 1]);
      final link = _StubLink(
        result: WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 1503,
              startTime: 1_700_600_000,
              endTime: 1_700_600_300,
              durationSec: 300,
              type: 140,
              load: 11,
              leftoverBytes: oldBytes,
              leftoverLen: oldBytes.length,
              samplePath:
                  '${GateAPrefs.workoutHrSamplesDir}/1503_1700600000.bin',
              sampleCount: 40,
              sampleFetch: 'ok',
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
      expect(await repo.syncFromWatch(), isA<Right>());

      final newBytes = Uint8List.fromList([9, 9, 9, 9, 9, 9]);
      link.result = WorkoutSyncResult(
        status: WorkoutSyncStatus.ok,
        workouts: [
          WorkoutSummary(
            number: 1503,
            startTime: 1_700_700_000,
            endTime: 1_700_700_500,
            durationSec: 500,
            type: 140,
            // load absent — new session must not inherit old 11
            leftoverBytes: newBytes,
            leftoverLen: newBytes.length,
          ),
        ],
      );
      expect(await repo.syncFromWatch(), isA<Right>());

      final newRel = WorkoutLeftoverStore.relativePathFor(
        workoutNumber: 1503,
        startTime: 1_700_700_000,
      );
      expect(await leftoverStore.loadAtRelativePath(newRel), newBytes);

      final local = await repo.loadLocal();
      expect(local, hasLength(1));
      expect(local.single.startTime, 1_700_700_000);
      expect(local.single.load, isNull);
      expect(local.single.leftoverPath, newRel);
      expect(local.single.leftoverLen, 6);
      expect(local.single.samplePath, isNull);
      expect(local.single.sampleCount, isNull);
    });

    test(
        'Totals-only swim re-pull does not empty richer canonical lap file',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u7_swim_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 1510,
              startTime: 1_700_800_000,
              endTime: 1_700_803_600,
              durationSec: 3600,
              type: 6,
              distanceM: 500,
              strokes: 350,
              avgSwolf: 165,
              poolLength: 2500,
              laps: 20,
              segments: [
                WorkoutSegment(
                  index: 0,
                  distanceM: 25,
                  durationSec: 40,
                  strokes: 18,
                  avgSwolf: 140,
                  style: 2,
                ),
                WorkoutSegment(
                  index: 1,
                  distanceM: 25,
                  durationSec: 42,
                  strokes: 19,
                  avgSwolf: 142,
                  style: 4,
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
      expect(await repo.syncFromWatch(), isA<Right>());
      final before = await repo.loadCanonicalSwim(1510);
      expect(before, isNotNull);
      expect(before!.p0.laps, hasLength(2));

      // Full-history Totals re-pull: looksLikeSwim but no segments/laps bodies.
      link.result = const WorkoutSyncResult(
        status: WorkoutSyncStatus.ok,
        workouts: [
          WorkoutSummary(
            number: 1510,
            startTime: 1_700_800_000,
            endTime: 1_700_803_600,
            durationSec: 3600,
            type: 6,
            distanceM: 500,
            strokes: 350,
            avgSwolf: 165,
            poolLength: 2500,
            laps: 20,
          ),
        ],
      );
      expect(await repo.syncFromWatch(), isA<Right>());

      final after = await repo.loadCanonicalSwim(1510);
      expect(after, isNotNull);
      expect(after!.p0.laps, hasLength(2));
      expect(after.p0.laps.map((l) => l.style).toList(), [2, 4]);
    });

    test('header-only Data must not wipe persisted sample points refs', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u7_header_');
      addTearDown(() => tmp.delete(recursive: true));

      final sampleRel =
          '${GateAPrefs.workoutHrSamplesDir}/1504_1700900000.bin';
      final sampleFile = File('${tmp.path}/$sampleRel');
      await sampleFile.parent.create(recursive: true);
      await sampleFile.writeAsBytes(List.filled(24, 3));

      final link = _StubLink(
        result: WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 1504,
              startTime: 1_700_900_000,
              endTime: 1_700_900_600,
              durationSec: 600,
              type: 140,
              dataCount: 1,
              samplePath: sampleRel,
              sampleCount: 90,
              sampleFetch: 'ok',
            ),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        leftoverRootOverride: () => tmp,
        sideFileRootOverride: () => tmp,
      );
      expect(await repo.syncFromWatch(), isA<Right>());

      // Header-only Data: dataCount hint, no points path / zero count.
      link.result = const WorkoutSyncResult(
        status: WorkoutSyncStatus.ok,
        workouts: [
          WorkoutSummary(
            number: 1504,
            startTime: 1_700_900_000,
            endTime: 1_700_900_600,
            durationSec: 600,
            type: 140,
            dataCount: 1,
            sampleCount: 0,
            sampleFetch: 'none',
          ),
        ],
      );
      expect(await repo.syncFromWatch(), isA<Right>());

      expect(await sampleFile.exists(), isTrue);
      final local = await repo.loadLocal();
      expect(local.single.samplePath, sampleRel);
      expect(local.single.sampleCount, 90);
      expect(local.single.sampleFetch, 'ok');
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
