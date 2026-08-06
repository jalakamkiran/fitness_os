import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/repositories/workout_history_repository_impl.dart';

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

    test('full-history sync when no cursor', () async {
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

      await repo.syncFromWatch();
      expect(
        link.lastStartUnix,
        WorkoutHistoryRepositoryImpl.fallbackStartUnix,
      );
    });

    test('full-history sync when any local workout is partial', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.lastSyncCursor: 1_800_000_000,
        GateAPrefs.swimSegmentParserVersion:
            WorkoutHistoryRepositoryImpl.currentSwimSegmentParserVersion,
        GateAPrefs.workoutsJson:
            '[{"number":1,"startTime":100,"endTime":200,"durationSec":100,'
                '"type":6,"enrichmentStatus":"partial"}]',
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
        WorkoutHistoryRepositoryImpl.fallbackStartUnix,
      );
    });

    test('full-history sync when swim segment parser version is stale',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.lastSyncCursor: 1_800_000_000,
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
        WorkoutHistoryRepositoryImpl.fallbackStartUnix,
      );
      expect(
        prefs.getInt(GateAPrefs.swimSegmentParserVersion),
        WorkoutHistoryRepositoryImpl.currentSwimSegmentParserVersion,
      );
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
  });
}
