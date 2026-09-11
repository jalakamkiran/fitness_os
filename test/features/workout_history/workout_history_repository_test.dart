import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/repositories/workout_history_repository_impl.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';

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

class _ThrowingRunSessionStore extends RunSessionStore {
  _ThrowingRunSessionStore({super.rootOverride});

  @override
  Future<void> save(PeeledWorkoutPayload payload) async {
    throw const FileSystemException('simulated side-file write failure');
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

    // --- U3 soft-incomplete merge (was CHARACTERIZATION Left reject) ---

    test('partial_batch with Totals merges prefs + leftovers; stamps partial',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u3_pb_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: WorkoutSyncResult.fromMap({
          'status': 'partial_batch',
          'message': 'Workout Sync incomplete — retry after reconnect',
          'workouts': [
            {
              'number': 70,
              'startTime': 1_700_000_000,
              'endTime': 1_700_003_600,
              'durationSec': 3600,
              'type': 2,
              'distanceM': 5000,
              'calories': 400,
              'leftoverBodies': [
                {'id': 0x66, 'len': 2, 'bodyBase64': 'qqo='},
              ],
            },
          ],
        }),
      );
      final store = RunSessionStore(rootOverride: () => tmp);
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: store,
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local, hasLength(1));
      expect(local.single.distanceM, 5000);
      expect(local.single.calories, 400);
      expect(local.single.enrichmentStatus, 'partial');
      expect(local.single.leftoversStatus, WorkoutStreamHonesty.present);
      // Honesty: partial ≠ “tiles absent”
      expect(prefs.getString(GateAPrefs.workoutsJson)!.contains('absent'),
          isFalse);
      expect((await store.loadTotalsLeftovers(70)).single.bodyBase64, 'qqo=');
    });

    test('stuck with earlier Totals merges those; incomplete overall', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u3_stuck_');
      addTearDown(() => tmp.delete(recursive: true));
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.stuck,
          message: 'Sync stuck — disconnect and reconnect',
          workouts: [
            WorkoutSummary(
              number: 71,
              startTime: 1_700_000_000,
              endTime: 1_700_001_000,
              durationSec: 1000,
              type: 2,
              distanceM: 3200,
            ),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: RunSessionStore(rootOverride: () => tmp),
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local.single.distanceM, 3200);
      expect(local.single.enrichmentStatus, 'partial');
    });

    test('stuck empty workouts stays Left (blocked honesty)', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.workoutsJson:
            '[{"number":1,"startTime":100,"endTime":200,"durationSec":100,"type":1}]',
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
      expect(await repo.loadLocal(), hasLength(1));
    });

    test('hard fail / notReady → Left; no absence claims; keeps prior',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.workoutsJson:
            '[{"number":9,"startTime":100,"endTime":200,"durationSec":100,'
                '"type":2,"distanceM":1000}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.notReady,
          message: 'Session not ready — reconnect',
          workouts: [],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(link: link, prefs: prefs);

      final out = await repo.syncFromWatch();
      expect(out, isA<Left>());
      final local = await repo.loadLocal();
      expect(local.single.distanceM, 1000);
      expect(prefs.getString(GateAPrefs.workoutsJson)!.contains('absent'),
          isFalse);
    });

    test('full ok stamps ok only when refs+files agree', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u3_ok_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: WorkoutSyncResult.fromMap({
          'status': 'ok',
          'workouts': [
            {
              'number': 72,
              'startTime': 1_700_000_000,
              'endTime': 1_700_003_600,
              'durationSec': 3600,
              'type': 2,
              'distanceM': 5000,
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
            },
          ],
        }),
      );
      final store = RunSessionStore(rootOverride: () => tmp);
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: store,
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local.single.enrichmentStatus, 'ok');
      expect(local.single.leftoversStatus, WorkoutStreamHonesty.present);
      expect(local.single.dataPagesStatus, WorkoutStreamHonesty.present);
      expect(local.single.paceBlocksStatus, WorkoutStreamHonesty.present);
      expect(await store.loadTotalsLeftovers(72), hasLength(1));
      expect(await store.loadDataPages(72), hasLength(1));
      expect(await store.loadPaceBlocks(72), hasLength(1));
    });

    test('later Totals-only Sync does not wipe richer side-files', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u3_mono_');
      addTearDown(() => tmp.delete(recursive: true));
      final store = RunSessionStore(rootOverride: () => tmp);

      final link = _StubLink(
        result: WorkoutSyncResult.fromMap({
          'status': 'ok',
          'workouts': [
            {
              'number': 73,
              'startTime': 1_700_000_000,
              'endTime': 1_700_003_600,
              'durationSec': 3600,
              'type': 2,
              'distanceM': 5000,
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
            },
          ],
        }),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: store,
        swimRootOverride: () => tmp,
      );
      await repo.syncFromWatch();
      expect(await store.loadDataPages(73), hasLength(1));

      // Totals-only re-sync (no stream bodies) — must retain side-files + stamps.
      link.result = WorkoutSyncResult.fromMap({
        'status': 'ok',
        'workouts': [
          {
            'number': 73,
            'startTime': 1_700_000_000,
            'endTime': 1_700_003_600,
            'durationSec': 3600,
            'type': 2,
            'distanceM': 5100,
            'calories': 450,
            'dataCount': 1,
            'paceCount': 1,
          },
        ],
      });
      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local.single.distanceM, 5100);
      expect(local.single.calories, 450);
      expect(local.single.dataPagesStatus, WorkoutStreamHonesty.present);
      expect(local.single.paceBlocksStatus, WorkoutStreamHonesty.present);
      expect(local.single.leftoversStatus, WorkoutStreamHonesty.present);
      expect(await store.loadDataPages(73), hasLength(1));
      expect(await store.loadPaceBlocks(73), hasLength(1));
      expect((await store.loadTotalsLeftovers(73)).single.bodyBase64, 'qqo=');
    });

    test('partial merge → next Sync start extends via partial-window overlap',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.lastSyncCursor: 1_690_000_000,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u3_cursor_');
      addTearDown(() => tmp.delete(recursive: true));
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.partialBatch,
          workouts: [
            WorkoutSummary(
              number: 74,
              startTime: 1_700_000_000,
              endTime: 1_700_001_000,
              durationSec: 1000,
              type: 2,
              distanceM: 2000,
            ),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: RunSessionStore(rootOverride: () => tmp),
        swimRootOverride: () => tmp,
      );

      final first = await repo.syncFromWatch();
      expect(first, isA<Right>());
      expect((await repo.loadLocal()).single.enrichmentStatus, 'partial');
      expect(prefs.getInt(GateAPrefs.lastSyncCursor), 1_700_001_001);

      link.result = const WorkoutSyncResult(
        status: WorkoutSyncStatus.empty,
        workouts: [],
      );
      await repo.syncFromWatch();
      expect(
        link.lastStartUnix,
        1_700_000_000 - WorkoutHistoryRepositoryImpl.cursorOverlapSec,
      );
    });

    test(
        'swim soft-incomplete Totals-only does not clobber richer segments',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u3_swim_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.ok,
          workouts: [
            WorkoutSummary(
              number: 75,
              startTime: 1_700_000_000,
              endTime: 1_700_000_500,
              durationSec: 500,
              type: 6,
              distanceM: 75,
              segmentsCount: 3,
              segments: [
                WorkoutSegment(index: 0, style: 2, distanceM: 25, strokes: 20),
                WorkoutSegment(index: 1, style: 4, distanceM: 25, strokes: 22),
                WorkoutSegment(index: 2, style: 1, distanceM: 25, strokes: 18),
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
      await repo.syncFromWatch();

      link.result = const WorkoutSyncResult(
        status: WorkoutSyncStatus.stuck,
        workouts: [
          WorkoutSummary(
            number: 75,
            startTime: 1_700_000_000,
            endTime: 1_700_000_500,
            durationSec: 500,
            type: 6,
            distanceM: 80,
            // Totals-only — no segments. Must not wipe richer local segments.
          ),
        ],
      );
      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local.single.type, 6);
      expect(local.single.distanceM, 80);
      expect(local.single.enrichmentStatus, 'partial');
      expect(local.single.segments, hasLength(3));
      expect(local.single.segments!.map((s) => s.style).toList(), [2, 4, 1]);
      // No invented Run tiles / outdoor fields.
      expect(local.single.dataPagesStatus, isNull);
      expect(local.single.paceBlocksStatus, isNull);
      final swim = await repo.loadCanonicalSwim(75);
      expect(swim!.p0.laps.map((l) => l.style).toList(), [2, 4, 1]);
    });

    test(
        'strength soft-incomplete merges Totals without inventing Run tiles',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_u3_str_');
      addTearDown(() => tmp.delete(recursive: true));
      final link = _StubLink(
        result: const WorkoutSyncResult(
          status: WorkoutSyncStatus.partialBatch,
          workouts: [
            WorkoutSummary(
              number: 76,
              startTime: 1_700_000_000,
              endTime: 1_700_000_900,
              durationSec: 900,
              type: 8,
              calories: 220,
              // Strength — no run stream invention.
            ),
          ],
        ),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: RunSessionStore(rootOverride: () => tmp),
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local.single.type, 8);
      expect(local.single.calories, 220);
      expect(local.single.enrichmentStatus, 'partial');
      expect(local.single.dataPagesStatus, isNull);
      expect(local.single.paceBlocksStatus, isNull);
      expect(local.single.leftoversStatus, isNull);
      expect(local.single.segments, isNull);
    });

    test('full ok Sync clears sticky enrichmentStatus partial', () {
      final merged = WorkoutEnrichmentMerge.mergeRow(
        existing: const WorkoutSummary(
          number: 78,
          startTime: 1_700_000_000,
          endTime: 1_700_001_000,
          durationSec: 1000,
          type: 2,
          enrichmentStatus: 'partial',
          leftoversStatus: WorkoutStreamHonesty.present,
          leftoverRefs: [EnrichmentTagRef(id: 0x66, len: 2)],
          parserGeneration: 1,
        ),
        incoming: const WorkoutSummary(
          number: 78,
          startTime: 1_700_000_000,
          endTime: 1_700_001_000,
          durationSec: 1000,
          type: 2,
          enrichmentStatus: 'ok',
          leftoversStatus: WorkoutStreamHonesty.present,
          leftoverRefs: [EnrichmentTagRef(id: 0x66, len: 2)],
          parserGeneration: 1,
        ),
        currentParserGeneration: 1,
      );
      expect(merged.enrichmentStatus, 'ok');
    });

    test('parserGeneration bump allows leftover/scalar replacement', () async {
      final merged = WorkoutEnrichmentMerge.mergeRow(
        existing: const WorkoutSummary(
          number: 77,
          startTime: 1_700_000_000,
          endTime: 1_700_001_000,
          durationSec: 1000,
          type: 2,
          distanceM: 4000,
          calories: 300,
          leftoversStatus: WorkoutStreamHonesty.present,
          leftoverRefs: [EnrichmentTagRef(id: 0x11, len: 4)],
          parserGeneration: 1,
        ),
        incoming: const WorkoutSummary(
          number: 77,
          startTime: 1_700_000_000,
          endTime: 1_700_001_000,
          durationSec: 1000,
          type: 2,
          distanceM: 4200,
          calories: 310,
          leftoversStatus: WorkoutStreamHonesty.present,
          leftoverRefs: [EnrichmentTagRef(id: 0x66, len: 2)],
          parserGeneration: 2,
        ),
        currentParserGeneration: 2,
      );
      expect(merged.distanceM, 4200);
      expect(merged.calories, 310);
      expect(merged.leftoverRefs!.single.id, 0x66);
      expect(merged.parserGeneration, 2);
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

    test('ok sync peels bodies into side-files; prefs lean without bodies',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_run_peel_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: WorkoutSyncResult.fromMap({
          'status': 'ok',
          'workouts': [
            {
              'number': 55,
              'startTime': 1_700_000_000,
              'endTime': 1_700_003_600,
              'durationSec': 3600,
              'type': 2,
              'distanceM': 5000,
              'dataCount': 1,
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
              'paceBlocks': [
                {
                  'index': 0,
                  'leftoverBodies': [
                    {'id': 0x7c, 'len': 1, 'bodyBase64': 'Aw=='},
                  ],
                },
              ],
            },
          ],
        }),
      );
      final store = RunSessionStore(rootOverride: () => tmp);
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: store,
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());

      final prefsRaw = prefs.getString(GateAPrefs.workoutsJson)!;
      expect(prefsRaw.contains('bodyBase64'), isFalse);
      expect(prefsRaw.contains('leftoverBodies'), isFalse);
      expect(prefsRaw.contains('"dataPages"'), isFalse);
      expect(prefsRaw.contains('"paceBlocks"'), isFalse);
      expect(prefsRaw.contains('dataPagesStatus'), isTrue);
      expect(prefsRaw.contains('paceBlocksStatus'), isTrue);

      final local = await repo.loadLocal();
      expect(local.single.leftoversStatus, WorkoutStreamHonesty.present);
      expect(local.single.dataPagesStatus, WorkoutStreamHonesty.present);
      expect(local.single.paceBlocksStatus, WorkoutStreamHonesty.present);
      expect(local.single.leftoverRefs!.single.id, 0x66);
      expect(local.single.observedType, 2);

      final leftovers = await store.loadTotalsLeftovers(55);
      expect(leftovers.single.bodyBase64, 'qqo=');
      expect((await store.loadDataPages(55)).single.bodies.single.bodyBase64,
          'AQ==');
      expect((await store.loadPaceBlocks(55)).single.bodies.single.bodyBase64,
          'Aw==');
    });

    test('ok sync Count=0 stamps unobserved and writes no stream files',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_run_count0_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: WorkoutSyncResult.fromMap({
          'status': 'ok',
          'workouts': [
            {
              'number': 56,
              'startTime': 1_700_000_000,
              'endTime': 1_700_001_000,
              'durationSec': 1000,
              'type': 2,
              'dataCount': 0,
              'paceCount': 0,
            },
          ],
        }),
      );
      final store = RunSessionStore(rootOverride: () => tmp);
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: store,
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local.single.dataPagesStatus, WorkoutStreamHonesty.unobserved);
      expect(local.single.paceBlocksStatus, WorkoutStreamHonesty.unobserved);
      expect(local.single.leftoversStatus, WorkoutStreamHonesty.unobserved);
      expect(
        await Directory('${tmp.path}/${GateAPrefs.workoutDataPagesDir}/56')
            .exists(),
        isFalse,
      );
    });

    test('partial pages persist arrived and stamp partial', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_run_partial_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: WorkoutSyncResult.fromMap({
          'status': 'ok',
          'workouts': [
            {
              'number': 57,
              'startTime': 1_700_000_000,
              'endTime': 1_700_001_000,
              'durationSec': 1000,
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
            },
          ],
        }),
      );
      final store = RunSessionStore(rootOverride: () => tmp);
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: store,
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local.single.dataPagesStatus, WorkoutStreamHonesty.partial);
      expect(local.single.paceBlocksStatus, WorkoutStreamHonesty.partial);
      expect(await store.loadDataPages(57), hasLength(1));
      expect(await store.loadPaceBlocks(57), hasLength(1));
    });

    test('side-file write failure stamps incomplete; Totals still merge',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_run_fail_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: WorkoutSyncResult.fromMap({
          'status': 'ok',
          'workouts': [
            {
              'number': 58,
              'startTime': 1_700_000_000,
              'endTime': 1_700_001_000,
              'durationSec': 1000,
              'type': 2,
              'distanceM': 4200,
              'calories': 300,
              'dataCount': 1,
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
            },
          ],
        }),
      );
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: _ThrowingRunSessionStore(rootOverride: () => tmp),
        swimRootOverride: () => tmp,
      );

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final local = await repo.loadLocal();
      expect(local, hasLength(1));
      expect(local.single.distanceM, 4200);
      expect(local.single.calories, 300);
      expect(local.single.leftoversStatus, WorkoutStreamHonesty.incomplete);
      expect(local.single.dataPagesStatus, WorkoutStreamHonesty.incomplete);
      // Prefs still lean — Totals mergeable for U3 even when streams incomplete.
      final prefsRaw = prefs.getString(GateAPrefs.workoutsJson)!;
      expect(prefsRaw.contains('bodyBase64'), isFalse);
      expect(prefsRaw.contains('"distanceM":4200'), isTrue);
    });

    test('run session clearLocal empties dirs after sync write', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('fos_run_wipe_');
      addTearDown(() => tmp.delete(recursive: true));

      final link = _StubLink(
        result: WorkoutSyncResult.fromMap({
          'status': 'ok',
          'workouts': [
            {
              'number': 59,
              'startTime': 1_700_000_000,
              'endTime': 1_700_001_000,
              'durationSec': 1000,
              'type': 2,
              'dataCount': 1,
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
            },
          ],
        }),
      );
      final store = RunSessionStore(rootOverride: () => tmp);
      final repo = WorkoutHistoryRepositoryImpl(
        link: link,
        prefs: prefs,
        runSessionStore: store,
        swimRootOverride: () => tmp,
      );
      await repo.syncFromWatch();
      expect(
        await Directory('${tmp.path}/${GateAPrefs.workoutTotalsLeftoversDir}/59')
            .exists(),
        isTrue,
      );
      await store.clearLocal();
      expect(
        await Directory('${tmp.path}/${GateAPrefs.workoutTotalsLeftoversDir}')
            .exists(),
        isFalse,
      );
      expect(
        await Directory('${tmp.path}/${GateAPrefs.workoutDataPagesDir}')
            .exists(),
        isFalse,
      );
    });
  });
}
