import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/vitals/domain/sleep_hr_window.dart';
import 'package:fitness_os/features/vitals/data/repositories/vitals_repository_impl.dart';
import 'package:fitness_os/features/vitals/domain/trusleep_sleep_sot.dart';

class _StubLink extends HuaweiLink {
  _StubLink({
    this.result,
    this.enableResult,
    this.sessionReadyOverride = true,
  });

  ActivitySyncResult? result;
  AutoTrackingEnableResult? enableResult;
  bool sessionReadyOverride;
  int activityCalls = 0;
  int enableCalls = 0;
  bool? lastSkipTruSleepSoft;
  bool? lastSkipAutoHrSoft;
  int? lastStartUnix;
  int? lastEndUnix;

  @override
  bool get sessionReady => sessionReadyOverride;

  @override
  Future<ActivitySyncResult> syncActivity({
    int? startUnix,
    int? endUnix,
    bool skipTruSleepSoft = false,
    bool skipAutoHrSoft = false,
  }) async {
    activityCalls++;
    lastStartUnix = startUnix;
    lastEndUnix = endUnix;
    lastSkipTruSleepSoft = skipTruSleepSoft;
    lastSkipAutoHrSoft = skipAutoHrSoft;
    return result ??
        const ActivitySyncResult(status: ActivitySyncStatus.empty);
  }

  @override
  Future<AutoTrackingEnableResult> enableAutoTracking() async {
    enableCalls++;
    return enableResult ??
        const AutoTrackingEnableResult(
          status: AutoTrackingEnableStatus.ok,
          overall: AutoTrackingOverall.allArmed,
          features: [
            AutoTrackingFeatureOutcome(id: 'trusleep', outcome: 'armed'),
            AutoTrackingFeatureOutcome(id: 'auto_hr', outcome: 'armed'),
            AutoTrackingFeatureOutcome(id: 'auto_spo2', outcome: 'armed'),
          ],
        );
  }
}

const _implV1 = VitalsRepositoryImpl.currentActivitySyncImplVersion;
const _overlapSec = VitalsRepositoryImpl.activityCursorOverlapSec;

Map<String, Object> _gateOpen({int? implVersion, int? cursor}) => {
      GateAPrefs.gateAPassed: true,
      if (implVersion != null) GateAPrefs.activitySyncImplVersion: implVersion,
      if (cursor != null) GateAPrefs.lastActivitySyncCursor: cursor,
    };

SleepEnrichOutcome _fileEnrich(List<SleepStateInterval> intervals) {
  var begin = intervals.first.beginUnix;
  var end = intervals.first.endUnix;
  for (final i in intervals.skip(1)) {
    if (i.beginUnix < begin) begin = i.beginUnix;
    if (i.endUnix > end) end = i.endUnix;
  }
  return SleepEnrichOutcome(
    beginUnix: begin,
    endUnix: end,
    present: true,
    stateIntervals: intervals,
    refs: const [SleepFileRef(id: 'sleep_state', len: 128)],
  );
}

ActivitySyncResult _fileSync({
  required List<SleepStateInterval> intervals,
  List<SleepSessionSummary> messages = const [],
  ActivitySyncStatus status = ActivitySyncStatus.ok,
  Set<String> completedContainers = const {'sleep'},
}) =>
    ActivitySyncResult(
      status: status,
      sleepSessions: messages,
      sleepEnrich: [_fileEnrich(intervals)],
      completedContainers: completedContainers,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VitalsRepositoryImpl', () {
    test('blocks sync when gate_a_passed is false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink();
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

      final out = await repo.syncFromWatch();
      expect(out, isA<Left>());
      expect(link.activityCalls, 0);
    });

    test('sync ok with overnight + nap; daily_hr not merged', () async {
      SharedPreferences.setMockInitialValues(_gateOpen(implVersion: _implV1));
      final prefs = await SharedPreferences.getInstance();
      const overnightBegin = 1700000000;
      const overnightEnd = overnightBegin + 8 * 3600;
      const napBegin = overnightEnd + 3600;
      const napEnd = napBegin + 40 * 60;
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          sleepSessions: [
            SleepSessionSummary(
              beginUnix: overnightBegin,
              endUnix: overnightEnd,
            ),
            SleepSessionSummary(beginUnix: napBegin, endUnix: napEnd),
          ],
          dailyHrSamples: [
            DailyHrSample(timestampUnix: overnightBegin + 12 * 3600, bpm: 70),
            DailyHrSample(
              timestampUnix: overnightBegin + 12 * 3600 + 60,
              bpm: 80,
            ),
          ],
          completedContainers: {'sleep', 'daily_hr'},
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final snap = (out as Right).value;
      expect(snap.sleepSessions, hasLength(2));
      expect(snap.dailyHr, isEmpty);
      expect(await repo.loadSleepSessions(), hasLength(2));
      expect(await repo.loadDailyHr(), isEmpty);
      expect(link.lastSkipAutoHrSoft, isTrue);
    });

    test('second sync empty keeps prior', () async {
      SharedPreferences.setMockInitialValues({
        ..._gateOpen(implVersion: _implV1),
        GateAPrefs.sleepSessionsJson:
            '[{"beginUnix":100,"endUnix":200}]',
        GateAPrefs.dailyHrJson:
            '[{"dayKey":"2023-11-14","minBpm":60,"avgBpm":70,"maxBpm":80,"sampleCount":2}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(status: ActivitySyncStatus.empty),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      expect(await repo.loadSleepSessions(), hasLength(1));
      expect(await repo.loadDailyHr(), hasLength(1));
    });

    test('partial_batch sleep-only leaves HR unchanged', () async {
      SharedPreferences.setMockInitialValues({
        ..._gateOpen(implVersion: _implV1),
        GateAPrefs.dailyHrJson:
            '[{"dayKey":"2023-11-14","minBpm":60,"avgBpm":70,"maxBpm":80,"sampleCount":2}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.partialBatch,
          sleepSessions: [
            SleepSessionSummary(beginUnix: 300, endUnix: 400),
          ],
          completedContainers: {'sleep'},
          message: 'partial',
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

      await repo.syncFromWatch();
      expect(await repo.loadSleepSessions(), hasLength(1));
      expect(await repo.loadDailyHr(), hasLength(1));
      expect((await repo.loadDailyHr()).first.dayKey, '2023-11-14');
    });

    test('upsert same begin/end twice → one session', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          sleepSessions: [
            SleepSessionSummary(beginUnix: 100, endUnix: 200),
            SleepSessionSummary(beginUnix: 100, endUnix: 200),
          ],
          completedContainers: {'sleep'},
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);
      await repo.syncFromWatch();
      expect(await repo.loadSleepSessions(), hasLength(1));
    });

    test('overlapping re-sync replaces fragmented prior sessions', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.sleepSessionsJson:
            '[{"beginUnix":100,"endUnix":200},{"beginUnix":180,"endUnix":300}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          sleepSessions: [
            SleepSessionSummary(beginUnix: 100, endUnix: 400),
          ],
          completedContainers: {'sleep'},
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);
      await repo.syncFromWatch();
      final sleep = await repo.loadSleepSessions();
      expect(sleep, hasLength(1));
      expect(sleep.first.beginUnix, 100);
      expect(sleep.first.endUnix, 400);
    });

    test('corrupt sleep JSON is fail-closed', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.sleepSessionsJson: '{not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = VitalsRepositoryImpl(
        link: _StubLink(),
        prefs: prefs,
      );
      expect(repo.loadSleepSessions(), throwsA(isA<FormatException>()));

      final out = await repo.syncFromWatch();
      // empty must not confirm wipe while corrupt
      expect(out, isA<Left>());
      expect(prefs.getString(GateAPrefs.sleepSessionsJson), '{not-json');
    });

    test('busy leaves stores unchanged', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.sleepSessionsJson:
            '[{"beginUnix":100,"endUnix":200}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.busy,
          message: 'Another Sync is already in progress',
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);
      final out = await repo.syncFromWatch();
      expect(out, isA<Left>());
      expect(await repo.loadSleepSessions(), hasLength(1));
    });

    test('clearLocal removes prefs keys; workouts untouched', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.sleepSessionsJson:
            '[{"beginUnix":100,"endUnix":200}]',
        GateAPrefs.dailyHrJson:
            '[{"dayKey":"2023-11-14","minBpm":60,"avgBpm":70,"maxBpm":80,"sampleCount":1}]',
        GateAPrefs.fitnessTotalsDayJson:
            '[{"dayKey":"2023-11-14","dayStartUnix":1700000000,"calories":10,"steps":100,"exerciseDurationSec":60}]',
        GateAPrefs.lastAutoTrackingEnableJson:
            '{"overall":"all_armed","features":[{"id":"auto_hr","outcome":"armed"}]}',
        GateAPrefs.workoutsJson:
            '[{"number":1,"startTime":1,"endTime":2,"durationSec":1,"type":1}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = VitalsRepositoryImpl(
        link: _StubLink(),
        prefs: prefs,
      );
      await repo.clearLocal();
      expect(prefs.getString(GateAPrefs.sleepSessionsJson), isNull);
      expect(prefs.getString(GateAPrefs.dailyHrJson), isNull);
      expect(prefs.getString(GateAPrefs.fitnessTotalsDayJson), isNull);
      expect(prefs.getString(GateAPrefs.lastAutoTrackingEnableJson), isNull);
      expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), isNull);
      expect(prefs.getInt(GateAPrefs.activitySyncImplVersion), isNull);
      expect(prefs.getString(GateAPrefs.workoutsJson), isNotNull);
    });

    test('enable persists last-run; Sync force-pulls TruSleep, soft-skips armed HR',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(status: ActivitySyncStatus.empty),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

      final enableOut = await repo.enableAutoTracking();
      expect(enableOut, isA<Right>());
      expect(link.enableCalls, 1);
      final loaded = await repo.loadLastEnable();
      expect(loaded?.outcomeFor('auto_hr'), 'armed');
      expect(loaded?.outcomeFor('auto_spo2'), 'armed');

      await repo.syncFromWatch();
      // Owner debug force-pull: always re-arm TruSleep soft-enable.
      expect(link.lastSkipTruSleepSoft, isFalse);
      expect(link.lastSkipAutoHrSoft, isTrue);
    });

    test('empty Sync with armed auto-HR uses wear/emission copy', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
        GateAPrefs.lastAutoTrackingEnableJson:
            '{"overall":"all_armed","features":['
            '{"id":"trusleep","outcome":"armed"},'
            '{"id":"auto_hr","outcome":"armed"},'
            '{"id":"auto_spo2","outcome":"armed"}]}',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.empty,
          enableSkipped: true,
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);
      final out = await repo.syncFromWatch();
      final snap = (out as Right).value;
      expect(snap.message, contains('continuous HR is not synced'));
      expect(snap.message, isNot(contains('Enable skipped')));
    });

    test('enable not ready when session down', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(sessionReadyOverride: false);
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);
      final out = await repo.enableAutoTracking();
      expect(out, isA<Left>());
      expect(link.enableCalls, 0);
    });

    test('corrupt last-enable JSON fail-closed', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.lastAutoTrackingEnableJson:
            '{"overall":"all_armed","features":[],"hexFrames":"deadbeef"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = VitalsRepositoryImpl(link: _StubLink(), prefs: prefs);
      expect(await repo.loadLastEnable(), isNull);
    });

    test('impl bump clears prior HR; sync never merges daily_hr', () async {
      final tempRoot = Directory.systemTemp.createTempSync('fos_hr_strip_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      SharedPreferences.setMockInitialValues({
        ..._gateOpen(),
        GateAPrefs.dailyHrJson:
            '[{"dayKey":"2024-01-01","minBpm":60,"avgBpm":70,"maxBpm":80,"sampleCount":2}]',
      });
      final prefs = await SharedPreferences.getInstance();
      const t0 = 1_704_067_200;
      final seriesDir =
          Directory('${tempRoot.path}/${GateAPrefs.dailyHrSeriesDir}');
      seriesDir.createSync(recursive: true);
      File('${seriesDir.path}/2024-01-01.json').writeAsStringSync(jsonEncode({
        'dayKey': '2024-01-01',
        'samples': [
          {'timestampUnix': t0, 'bpm': 65},
        ],
      }));

      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          dailyHrSamples: [
            DailyHrSample(timestampUnix: t0 + 60, bpm: 72),
          ],
          completedContainers: {'daily_hr'},
        ),
      );
      final repo = VitalsRepositoryImpl(
        link: link,
        prefs: prefs,
        sideFileRootOverride: () => tempRoot,
      );

      await repo.syncFromWatch();
      expect(await repo.loadDailyHr(), isEmpty);
      expect(await repo.loadDailyHrSeries('2024-01-01'), isEmpty);
      expect(prefs.getInt(GateAPrefs.activitySyncImplVersion), _implV1);
      expect(link.lastSkipAutoHrSoft, isTrue);
    });

    test('daily HR series roundtrip via side-file (seeded, no sync merge)',
        () async {
      final tempRoot = Directory.systemTemp.createTempSync('fos_hr_series_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      SharedPreferences.setMockInitialValues(_gateOpen(implVersion: _implV1));
      final prefs = await SharedPreferences.getInstance();
      const t0 = 1_704_067_200;
      const t1 = t0 + 60;
      const t2 = t0 + 120;
      final repo = VitalsRepositoryImpl(
        link: _StubLink(),
        prefs: prefs,
        sideFileRootOverride: () => tempRoot,
      );

      await prefs.setString(
        GateAPrefs.dailyHrJson,
        jsonEncode([
          {
            'dayKey': '2024-01-01',
            'minBpm': 65,
            'avgBpm': 68,
            'maxBpm': 72,
            'sampleCount': 3,
          },
        ]),
      );
      final seriesDir =
          Directory('${tempRoot.path}/${GateAPrefs.dailyHrSeriesDir}');
      await seriesDir.create(recursive: true);
      await File('${seriesDir.path}/2024-01-01.json').writeAsString(
        jsonEncode({
          'dayKey': '2024-01-01',
          'samples': [
            {'timestampUnix': t0, 'bpm': 65},
            {'timestampUnix': t1, 'bpm': 72},
            {'timestampUnix': t2, 'bpm': 68},
          ],
        }),
      );

      final hrDays = await repo.loadDailyHr();
      expect(hrDays, hasLength(1));
      final dayKey = hrDays.first.dayKey;
      final series = await repo.loadDailyHrSeries(dayKey);
      expect(series, hasLength(3));
      expect(series.map((s) => s.bpm).toList(), [65, 72, 68]);
      expect(hrDays.first.sampleCount, 3);

      await repo.clearLocal();
      expect(await repo.loadDailyHrSeries(dayKey), isEmpty);
      expect(await repo.loadDailyHr(), isEmpty);
    });

    test('sleep stages round-trip via side-file; prefs stay lean', () async {
      final tempRoot = Directory.systemTemp.createTempSync('fos_sleep_stages_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      const begin = 1_700_000_000;
      const end = begin + 3 * 3600;
      final session = SleepSessionSummary(
        beginUnix: begin,
        endUnix: end,
        wireType: 1,
        stages: const [
          SleepStageSummary(timestampUnix: begin, durationMin: 60, wireType: 1),
          SleepStageSummary(
            timestampUnix: begin + 3600,
            durationMin: 60,
            wireType: 3,
          ),
          SleepStageSummary(
            timestampUnix: begin + 7200,
            durationMin: 60,
            wireType: 2,
          ),
        ],
      );
      final link = _StubLink(
        result: ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          sleepSessions: [session],
          completedContainers: {'sleep'},
        ),
      );
      final repo = VitalsRepositoryImpl(
        link: link,
        prefs: prefs,
        sideFileRootOverride: () => tempRoot,
      );

      await repo.syncFromWatch();
      final stored = await repo.loadSleepSessions();
      expect(stored, hasLength(1));
      expect(stored.first.stages, isEmpty); // lean prefs
      final prefsRaw = prefs.getString(GateAPrefs.sleepSessionsJson)!;
      expect(prefsRaw.contains('stages'), isFalse);

      final stages = await repo.loadSleepStages(stored.first);
      expect(stages, hasLength(3));
      expect(stages.map((s) => s.wireType).toList(), [1, 3, 2]);

      // Corrupt stage file fail-closed without wiping begin/end prefs.
      final stageFiles =
          Directory('${tempRoot.path}/${GateAPrefs.sleepStagesDir}')
              .listSync()
              .whereType<File>()
              .toList();
      expect(stageFiles, hasLength(1));
      stageFiles.first.writeAsStringSync('{not-json');
      expect(await repo.loadSleepStages(stored.first), isEmpty);
      expect(await repo.loadSleepSessions(), hasLength(1));

      await repo.clearLocal();
      expect(await repo.loadSleepStages(session), isEmpty);
      expect(await repo.loadSleepSessions(), isEmpty);
    });

    test('force-pull Sync replaces sleep store; empty stages wipe prior files',
        () async {
      final tempRoot = Directory.systemTemp.createTempSync('fos_sleep_keep_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      const begin = 1_700_000_000;
      const end = begin + 3 * 3600;
      final withStages = SleepSessionSummary(
        beginUnix: begin,
        endUnix: end,
        stages: const [
          SleepStageSummary(timestampUnix: begin, durationMin: 60, wireType: 1),
          SleepStageSummary(
            timestampUnix: begin + 3600,
            durationMin: 60,
            wireType: 3,
          ),
        ],
      );
      final repo = VitalsRepositoryImpl(
        link: _StubLink(
          result: ActivitySyncResult(
            status: ActivitySyncStatus.ok,
            sleepSessions: [withStages],
            completedContainers: {'sleep'},
          ),
        ),
        prefs: prefs,
        sideFileRootOverride: () => tempRoot,
      );
      await repo.syncFromWatch();
      expect(await repo.loadSleepStages(withStages), hasLength(2));

      final emptyStages = SleepSessionSummary(beginUnix: begin, endUnix: end);
      final repo2 = VitalsRepositoryImpl(
        link: _StubLink(
          result: ActivitySyncResult(
            status: ActivitySyncStatus.ok,
            sleepSessions: [emptyStages],
            completedContainers: {'sleep'},
          ),
        ),
        prefs: prefs,
        sideFileRootOverride: () => tempRoot,
      );
      await repo2.syncFromWatch();
      expect(await repo2.loadSleepSessions(), hasLength(1));
      // Force-pull replaces SoT — empty incoming stages clears prior side-file.
      expect(await repo2.loadSleepStages(emptyStages), isEmpty);
    });

    test('overnight sleep HR window loads both dayKeys (seeded)', () async {
      final tempRoot = Directory.systemTemp.createTempSync('fos_sleep_hr_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      SharedPreferences.setMockInitialValues(_gateOpen(implVersion: _implV1));
      final prefs = await SharedPreferences.getInstance();
      final midnight =
          DateTime(2024, 6, 2).millisecondsSinceEpoch ~/ 1000;
      final before = midnight - 30 * 60;
      final after = midnight + 30 * 60;
      final outside = midnight - 3 * 3600;

      final repo = VitalsRepositoryImpl(
        link: _StubLink(),
        prefs: prefs,
        sideFileRootOverride: () => tempRoot,
      );
      final dayKeys = sleepHrDayKeys(
        beginUnix: before - 60,
        endUnix: after + 60,
      );
      expect(dayKeys, hasLength(2));
      await prefs.setString(
        GateAPrefs.dailyHrJson,
        jsonEncode([
          for (final k in dayKeys)
            {'dayKey': k, 'minBpm': 55, 'avgBpm': 60, 'maxBpm': 70, 'sampleCount': 2},
        ]),
      );
      final seriesDir =
          Directory('${tempRoot.path}/${GateAPrefs.dailyHrSeriesDir}');
      await seriesDir.create(recursive: true);
      await File('${seriesDir.path}/${dayKeys[0]}.json').writeAsString(jsonEncode({
        'dayKey': dayKeys[0],
        'samples': [
          {'timestampUnix': outside, 'bpm': 55},
          {'timestampUnix': before, 'bpm': 58},
        ],
      }));
      await File('${seriesDir.path}/${dayKeys[1]}.json').writeAsString(jsonEncode({
        'dayKey': dayKeys[1],
        'samples': [
          {'timestampUnix': after, 'bpm': 62},
          {'timestampUnix': midnight + 3 * 3600, 'bpm': 70},
        ],
      }));

      final window = await repo.loadSleepHrWindow(
        beginUnix: before - 60,
        endUnix: after + 60,
      );
      expect(window.map((s) => s.bpm).toList(), [58, 62]);

      expect(
        await repo.loadSleepHrWindow(beginUnix: before, endUnix: before),
        isEmpty,
      );
      expect(
        await repo.loadSleepHrWindow(beginUnix: after, endUnix: before),
        isEmpty,
      );
    });

    test('fileDownload enrich absent keeps sleep; present sets enrich flag', () async {
      final tempRoot = Directory.systemTemp.createTempSync('fos_sleep_enrich_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      const begin = 1_700_000_000;
      const end = begin + 3 * 3600;
      final session = SleepSessionSummary(beginUnix: begin, endUnix: end);
      final absentLink = _StubLink(
        result: ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          sleepSessions: [session],
          completedContainers: {'sleep'},
          sleepEnrich: const [],
        ),
      );
      final repo = VitalsRepositoryImpl(
        link: absentLink,
        prefs: prefs,
        sideFileRootOverride: () => tempRoot,
      );
      await repo.syncFromWatch();
      expect(await repo.loadSleepSessions(), hasLength(1));
      expect(await repo.isSleepEnrichPresent(session), isFalse);

      final presentLink = _StubLink(
        result: ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          sleepSessions: [session],
          completedContainers: {'sleep'},
          sleepEnrich: [
            SleepEnrichOutcome(
              beginUnix: begin,
              endUnix: end,
              present: true,
              refs: const [
                SleepFileRef(id: 'sleep_state', len: 128),
              ],
            ),
          ],
        ),
      );
      final repo2 = VitalsRepositoryImpl(
        link: presentLink,
        prefs: prefs,
        sideFileRootOverride: () => tempRoot,
      );
      await repo2.syncFromWatch();
      expect(await repo2.loadSleepSessions(), hasLength(1));
      expect(await repo2.isSleepEnrichPresent(session), isTrue);
    });

    test('feel-on-wake once per session key + month filter', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.sleepSessionsJson: jsonEncode([
          {
            'beginUnix': DateTime(2024, 5, 10, 23).millisecondsSinceEpoch ~/ 1000,
            'endUnix': DateTime(2024, 5, 11, 6).millisecondsSinceEpoch ~/ 1000,
          },
          {
            'beginUnix': DateTime(2024, 6, 1, 23).millisecondsSinceEpoch ~/ 1000,
            'endUnix': DateTime(2024, 6, 2, 6).millisecondsSinceEpoch ~/ 1000,
          },
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = VitalsRepositoryImpl(link: _StubLink(), prefs: prefs);
      final june = await repo.loadSleepSessionsForMonth(year: 2024, month: 6);
      expect(june, hasLength(1));
      final may = await repo.loadSleepSessionsForMonth(year: 2024, month: 5);
      expect(may, hasLength(1));
      expect(
        await repo.loadSleepSessionsForMonth(year: 2024, month: 4),
        isEmpty,
      );

      final session = june.first;
      expect(await repo.loadFeelOnWake(session), isNull);
      await repo.saveFeelOnWake(session, 'good');
      expect(await repo.loadFeelOnWake(session), 'good');
      await repo.saveFeelOnWake(session, 'great'); // once-per-key
      expect(await repo.loadFeelOnWake(session), 'good');
    });

    test('fitness totals merge persists today row including zeros', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          fitnessTotals: [
            FitnessTotalsDay(
              dayKey: '2024-01-01',
              dayStartUnix: 1704067200,
              calories: 966,
              steps: 8500,
              exerciseDurationSec: 7620,
            ),
            FitnessTotalsDay(
              dayKey: '2023-12-31',
              dayStartUnix: 1703980800,
              calories: 0,
              steps: 0,
              exerciseDurationSec: 0,
            ),
          ],
          completedContainers: {'fitness_totals'},
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      final days = await repo.loadFitnessTotals();
      expect(days, hasLength(2));
      final today = await repo.loadFitnessTotalsForDay('2024-01-01');
      expect(today?.calories, 966);
      expect(today?.steps, 8500);
      expect(today?.exerciseDurationSec, 7620);
      final zeroDay = await repo.loadFitnessTotalsForDay('2023-12-31');
      expect(zeroDay?.calories, 0);
      expect(zeroDay?.steps, 0);
    });

    test('totals-only ok payload merges without sleep or HR', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          fitnessTotals: [
            FitnessTotalsDay(
              dayKey: '2024-01-01',
              dayStartUnix: 1704067200,
              calories: 5,
              steps: 10,
              exerciseDurationSec: 60,
            ),
          ],
          completedContainers: {'fitness_totals'},
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);
      await repo.syncFromWatch();
      expect(await repo.loadSleepSessions(), isEmpty);
      expect(await repo.loadDailyHr(), isEmpty);
      expect(await repo.loadFitnessTotals(), hasLength(1));
      expect(prefs.getString(GateAPrefs.fitnessTotalsDayJson), isNotNull);
    });

    test('second fitness totals sync replaces same dayKey and keeps others',
        () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.fitnessTotalsDayJson:
            '[{"dayKey":"2024-01-01","dayStartUnix":1704067200,"calories":1,"steps":1,"exerciseDurationSec":1},'
            '{"dayKey":"2023-12-30","dayStartUnix":1703894400,"calories":9,"steps":9,"exerciseDurationSec":9}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          fitnessTotals: [
            FitnessTotalsDay(
              dayKey: '2024-01-01',
              dayStartUnix: 1704067200,
              calories: 966,
              steps: 8500,
              exerciseDurationSec: 7620,
            ),
          ],
          completedContainers: {'fitness_totals'},
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);
      await repo.syncFromWatch();
      final days = await repo.loadFitnessTotals();
      expect(days, hasLength(2));
      expect(
        days.firstWhere((d) => d.dayKey == '2024-01-01').calories,
        966,
      );
      expect(
        days.firstWhere((d) => d.dayKey == '2023-12-30').calories,
        9,
      );
    });

    test('incomplete fitness_totals container keeps prior prefs', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.fitnessTotalsDayJson:
            '[{"dayKey":"2024-01-01","dayStartUnix":1704067200,"calories":50,"steps":100,"exerciseDurationSec":600}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final link = _StubLink(
        result: const ActivitySyncResult(
          status: ActivitySyncStatus.ok,
          sleepSessions: [
            SleepSessionSummary(beginUnix: 100, endUnix: 200),
          ],
          fitnessTotals: [
            FitnessTotalsDay(
              dayKey: '2024-01-01',
              dayStartUnix: 1704067200,
              calories: 999,
              steps: 999,
              exerciseDurationSec: 999,
            ),
          ],
          completedContainers: {'sleep'}, // fitness_totals absent
        ),
      );
      final repo = VitalsRepositoryImpl(link: link, prefs: prefs);
      await repo.syncFromWatch();
      final today = await repo.loadFitnessTotalsForDay('2024-01-01');
      expect(today?.calories, 50);
      expect(today?.steps, 100);
    });

    test('corrupt fitness totals JSON is fail-closed', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.fitnessTotalsDayJson: '{not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = VitalsRepositoryImpl(
        link: _StubLink(
          result: const ActivitySyncResult(
            status: ActivitySyncStatus.ok,
            fitnessTotals: [
              FitnessTotalsDay(
                dayKey: '2024-01-01',
                dayStartUnix: 1704067200,
                calories: 1,
                steps: 1,
                exerciseDurationSec: 1,
              ),
            ],
            completedContainers: {'fitness_totals'},
          ),
        ),
        prefs: prefs,
      );
      expect(repo.loadFitnessTotals(), throwsA(isA<FormatException>()));

      final out = await repo.syncFromWatch();
      expect(out, isA<Right>());
      // fail-closed: do not overwrite corrupt store
      expect(prefs.getString(GateAPrefs.fitnessTotalsDayJson), '{not-json');
    });

    test('empty sync with corrupt fitness totals does not wipe', () async {
      SharedPreferences.setMockInitialValues({
        GateAPrefs.gateAPassed: true,
        GateAPrefs.fitnessTotalsDayJson: '{not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = VitalsRepositoryImpl(
        link: _StubLink(
          result: const ActivitySyncResult(status: ActivitySyncStatus.empty),
        ),
        prefs: prefs,
      );
      final out = await repo.syncFromWatch();
      expect(out, isA<Left>());
      expect(prefs.getString(GateAPrefs.fitnessTotalsDayJson), '{not-json');
    });

    group('TruSleep file-primary SoT', () {
      test('file intervals → gap-merged prefs; cursor advances on ok', () async {
        SharedPreferences.setMockInitialValues(_gateOpen(implVersion: _implV1));
        final prefs = await SharedPreferences.getInstance();
        const i1 = SleepStateInterval(beginUnix: 1000, endUnix: 2000);
        const i2 = SleepStateInterval(beginUnix: 2100, endUnix: 3000);
        const i3 = SleepStateInterval(beginUnix: 5000, endUnix: 6000);
        final link = _StubLink(
          result: _fileSync(intervals: const [i1, i2, i3]),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        await repo.syncFromWatch();
        final sleep = await repo.loadSleepSessions();
        expect(sleep, hasLength(2));
        expect(sleep.any((s) => s.beginUnix == 1000 && s.endUnix == 3000), isTrue);
        expect(sleep.any((s) => s.beginUnix == 5000 && s.endUnix == 6000), isTrue);
        expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), 6001);
        expect(link.lastStartUnix, isNotNull);
        expect(link.lastEndUnix, isNotNull);
      });

      test('messages empty + intervals → file sessions; cursor advances',
          () async {
        SharedPreferences.setMockInitialValues(_gateOpen(implVersion: _implV1));
        final prefs = await SharedPreferences.getInstance();
        const i1 = SleepStateInterval(beginUnix: 5000, endUnix: 8000);
        final link = _StubLink(
          result: _fileSync(intervals: const [i1], messages: const []),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        await repo.syncFromWatch();
        final sleep = await repo.loadSleepSessions();
        expect(sleep, hasLength(1));
        expect(sleep.first.beginUnix, 5000);
        expect(sleep.first.endUnix, 8000);
        expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), 8001);
      });

      test('wide then incremental: second sync start ≈ cursor − overlap',
          () async {
        SharedPreferences.setMockInitialValues(_gateOpen());
        final prefs = await SharedPreferences.getInstance();
        final endUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final fileEnd = endUnix - 3600;
        final fileBegin = fileEnd - 8 * 3600;
        final link = _StubLink(
          result: _fileSync(
            intervals: [
              SleepStateInterval(beginUnix: fileBegin, endUnix: fileEnd),
            ],
          ),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        await repo.syncFromWatch();
        final cursor = prefs.getInt(GateAPrefs.lastActivitySyncCursor);
        expect(cursor, fileEnd + 1);
        expect(prefs.getInt(GateAPrefs.activitySyncImplVersion), _implV1);

        link.result = const ActivitySyncResult(status: ActivitySyncStatus.empty);
        await repo.syncFromWatch();

        expect(link.lastStartUnix, cursor! - _overlapSec);
      });

      test('incremental upsert retains prior nights outside pull', () async {
        SharedPreferences.setMockInitialValues({
          ..._gateOpen(implVersion: _implV1, cursor: 1_700_100_001),
          GateAPrefs.sleepSessionsJson: jsonEncode([
            {'beginUnix': 1_699_000_000, 'endUnix': 1_699_010_000},
            {'beginUnix': 1_699_500_000, 'endUnix': 1_699_510_000},
          ]),
        });
        final prefs = await SharedPreferences.getInstance();
        const lastNight = SleepStateInterval(
          beginUnix: 1_700_090_000,
          endUnix: 1_700_100_000,
        );
        final link = _StubLink(
          result: _fileSync(intervals: const [lastNight]),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        await repo.syncFromWatch();
        final sleep = await repo.loadSleepSessions();
        expect(sleep, hasLength(3));
        expect(
          sleep.map((s) => s.beginUnix).toSet(),
          containsAll([1_699_000_000, 1_699_500_000, 1_700_090_000]),
        );
        expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), 1_700_100_001);
      });

      test('messages-only after flip: display windows + cursor unchanged',
          () async {
        SharedPreferences.setMockInitialValues({
          ..._gateOpen(implVersion: _implV1, cursor: 5001),
          GateAPrefs.sleepSessionsJson:
              '[{"beginUnix":1000,"endUnix":3000},{"beginUnix":5000,"endUnix":6000}]',
        });
        final prefs = await SharedPreferences.getInstance();
        final link = _StubLink(
          result: const ActivitySyncResult(
            status: ActivitySyncStatus.ok,
            sleepSessions: [
              SleepSessionSummary(beginUnix: 900, endUnix: 7000),
            ],
            sleepEnrich: [],
            completedContainers: {'sleep'},
          ),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        await repo.syncFromWatch();
        final sleep = await repo.loadSleepSessions();
        expect(sleep, hasLength(2));
        expect(sleep.any((s) => s.beginUnix == 1000 && s.endUnix == 3000), isTrue);
        expect(sleep.any((s) => s.beginUnix == 5000 && s.endUnix == 6000), isTrue);
        expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), 5001);
      });

      test('enrich absent with prior file SoT → keep prior; cursor unchanged',
          () async {
        SharedPreferences.setMockInitialValues({
          ..._gateOpen(implVersion: _implV1, cursor: 8001),
          GateAPrefs.sleepSessionsJson:
              '[{"beginUnix":5000,"endUnix":8000}]',
        });
        final prefs = await SharedPreferences.getInstance();
        final link = _StubLink(
          result: const ActivitySyncResult(
            status: ActivitySyncStatus.ok,
            sleepSessions: [
              SleepSessionSummary(beginUnix: 4800, endUnix: 8200),
            ],
            sleepEnrich: [],
            completedContainers: {'sleep'},
          ),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        await repo.syncFromWatch();
        final sleep = await repo.loadSleepSessions();
        expect(sleep, hasLength(1));
        expect(sleep.first.beginUnix, 5000);
        expect(sleep.first.endUnix, 8000);
        expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), 8001);
      });

      test('empty sync → no wipe; cursor unchanged', () async {
        SharedPreferences.setMockInitialValues({
          ..._gateOpen(implVersion: _implV1, cursor: 3001),
          GateAPrefs.sleepSessionsJson:
              '[{"beginUnix":1000,"endUnix":3000}]',
        });
        final prefs = await SharedPreferences.getInstance();
        final link = _StubLink(
          result: const ActivitySyncResult(status: ActivitySyncStatus.empty),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        final out = await repo.syncFromWatch();
        expect(out, isA<Right>());
        expect(await repo.loadSleepSessions(), hasLength(1));
        expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), 3001);
      });

      test('error sync → no wipe; cursor unchanged', () async {
        SharedPreferences.setMockInitialValues({
          ..._gateOpen(implVersion: _implV1, cursor: 3001),
          GateAPrefs.sleepSessionsJson:
              '[{"beginUnix":1000,"endUnix":3000}]',
        });
        final prefs = await SharedPreferences.getInstance();
        final link = _StubLink(
          result: const ActivitySyncResult(
            status: ActivitySyncStatus.error,
            message: 'fd fail',
          ),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        final out = await repo.syncFromWatch();
        expect(out, isA<Left>());
        expect(await repo.loadSleepSessions(), hasLength(1));
        expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), 3001);
      });

      test('totals-only ok → cursor unchanged', () async {
        SharedPreferences.setMockInitialValues({
          ..._gateOpen(implVersion: _implV1, cursor: 4001),
        });
        final prefs = await SharedPreferences.getInstance();
        final link = _StubLink(
          result: const ActivitySyncResult(
            status: ActivitySyncStatus.ok,
            fitnessTotals: [
              FitnessTotalsDay(
                dayKey: '2024-01-01',
                dayStartUnix: 1704067200,
                calories: 5,
                steps: 10,
                exerciseDurationSec: 60,
              ),
            ],
            completedContainers: {'fitness_totals'},
          ),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        await repo.syncFromWatch();
        expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), 4001);
        expect(await repo.loadFitnessTotals(), hasLength(1));
      });

      test('partialBatch with intervals upserts but cursor NOT advanced',
          () async {
        SharedPreferences.setMockInitialValues({
          ..._gateOpen(implVersion: _implV1, cursor: 2001),
        });
        final prefs = await SharedPreferences.getInstance();
        const i1 = SleepStateInterval(beginUnix: 1000, endUnix: 2000);
        final link = _StubLink(
          result: _fileSync(
            intervals: const [i1],
            status: ActivitySyncStatus.partialBatch,
          ),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        final out = await repo.syncFromWatch();
        expect(out, isA<Right>());
        final snap = (out as Right).value;
        expect(snap.partial, isTrue);
        expect(await repo.loadSleepSessions(), hasLength(1));
        expect(prefs.getInt(GateAPrefs.lastActivitySyncCursor), 2001);
      });

      test('~30m shift attaches message stages onto file window', () async {
        final tempRoot = Directory.systemTemp.createTempSync('fos_file_stages_');
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        SharedPreferences.setMockInitialValues(_gateOpen(implVersion: _implV1));
        final prefs = await SharedPreferences.getInstance();
        const fileBegin = 10_000;
        const fileEnd = 20_000;
        const shiftSec = VitalsRepositoryImpl.stageAttachBufferSec;
        const msgBegin = fileBegin - shiftSec + 60;
        const msgEnd = fileEnd - 600;
        const stageTs = fileBegin + 3600;
        final link = _StubLink(
          result: _fileSync(
            intervals: const [
              SleepStateInterval(beginUnix: fileBegin, endUnix: fileEnd),
            ],
            messages: [
              SleepSessionSummary(
                beginUnix: msgBegin,
                endUnix: msgEnd,
                stages: const [
                  SleepStageSummary(
                    timestampUnix: stageTs,
                    durationMin: 30,
                    wireType: 1,
                  ),
                ],
              ),
            ],
          ),
        );
        final repo = VitalsRepositoryImpl(
          link: link,
          prefs: prefs,
          sideFileRootOverride: () => tempRoot,
        );

        await repo.syncFromWatch();
        final sleep = await repo.loadSleepSessions();
        expect(sleep, hasLength(1));
        expect(sleep.first.beginUnix, fileBegin);
        expect(sleep.first.endUnix, fileEnd);
        final stages = await repo.loadSleepStages(sleep.first);
        expect(stages, hasLength(1));
        expect(stages.first.timestampUnix, stageTs);
      });

      test('feel-on-wake migrates to file window with longest overlap',
          () async {
        SharedPreferences.setMockInitialValues({
          ..._gateOpen(implVersion: _implV1),
          GateAPrefs.sleepSessionsJson: jsonEncode([
            {'beginUnix': 9000, 'endUnix': 19_000},
          ]),
          GateAPrefs.sleepFeelOnWakeJson: jsonEncode({
            '9000:19000:': 'good',
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        const i1 = SleepStateInterval(beginUnix: 10_000, endUnix: 20_000);
        final link = _StubLink(
          result: _fileSync(
            intervals: const [i1],
            messages: const [
              SleepSessionSummary(beginUnix: 9000, endUnix: 19_000),
            ],
          ),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        await repo.syncFromWatch();
        final sleep = await repo.loadSleepSessions();
        expect(sleep, hasLength(1));
        expect(await repo.loadFeelOnWake(sleep.first), 'good');
        expect(
          (jsonDecode(prefs.getString(GateAPrefs.sleepFeelOnWakeJson)!)
              as Map)
              .containsKey('9000:19000:'),
          isFalse,
        );
      });

      test('pickHeroSession prefers recent overnight (builder smoke)',
          () async {
        const now = 1_700_100_000;
        const recent = SleepSessionSummary(
          beginUnix: now - 8 * 3600,
          endUnix: now - 3600,
        );
        const olderLong = SleepSessionSummary(
          beginUnix: now - 72 * 3600,
          endUnix: now - 64 * 3600,
        );
        final hero = TruSleepSleepSot.pickHeroSession(
          const [olderLong, recent],
          nowUnix: now,
        );
        expect(hero?.beginUnix, recent.beginUnix);
      });

      test('skipAutoHrSoft always true on sync', () async {
        SharedPreferences.setMockInitialValues(_gateOpen(implVersion: _implV1));
        final prefs = await SharedPreferences.getInstance();
        final link = _StubLink(
          result: const ActivitySyncResult(status: ActivitySyncStatus.empty),
        );
        final repo = VitalsRepositoryImpl(link: link, prefs: prefs);

        await repo.syncFromWatch();
        expect(link.lastSkipAutoHrSoft, isTrue);
        expect(link.lastSkipTruSleepSoft, isFalse);
      });
    });
  });
}
