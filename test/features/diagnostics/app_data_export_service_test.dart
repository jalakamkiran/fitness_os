import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_envelope.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_service.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('fos_export_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<AppDataExportService> buildService({
    Map<String, Object> prefsSeed = const {},
    bool Function()? syncInFlight,
    bool Function()? vitalsBusy,
    bool Function()? forgetInFlight,
    Future<bool> Function()? qwenInstalled,
  }) async {
    SharedPreferences.setMockInitialValues(prefsSeed);
    final prefs = await SharedPreferences.getInstance();
    return AppDataExportService(
      prefs: prefs,
      sideFileRootOverride: () => tempRoot,
      exportCacheRootOverride: () => tempRoot,
      isSyncInFlight: syncInFlight ?? () => false,
      isVitalsSyncOrMergeInFlight: vitalsBusy ?? () => false,
      isForgetInFlight: forgetInFlight ?? () => false,
      isQwenInstalled: qwenInstalled ?? () async => false,
      clock: () => DateTime.utc(2026, 8, 5, 12, 0, 0),
    );
  }

  Future<void> writeSwim(int number, Map<String, Object?> body) async {
    final dir = Directory('${tempRoot.path}/${GateAPrefs.canonicalSwimDir}');
    await dir.create(recursive: true);
    await File('${dir.path}/swim_$number.json')
        .writeAsString(jsonEncode(body));
  }

  Future<void> writeHrDay(String dayKey, Object body) async {
    final dir = Directory('${tempRoot.path}/${GateAPrefs.dailyHrSeriesDir}');
    await dir.create(recursive: true);
    await File('${dir.path}/$dayKey.json').writeAsString(
      body is String ? body : jsonEncode(body),
    );
  }

  group('U1 assemble envelope', () {
    test('happy path: seeded prefs + swim + HR → counts and stamps', () async {
      await writeSwim(1, {
        'workoutNumber': 1,
        'startTime': 100,
        'type': 6,
      });
      await writeHrDay('2026-08-01', {
        'dayKey': '2026-08-01',
        'samples': [
          {'timestampUnix': 1, 'bpm': 60},
        ],
      });

      final service = await buildService(
        prefsSeed: {
          GateAPrefs.workoutsJson:
              '[{"number":1,"startTime":100,"endTime":200,"durationSec":100,"type":6,"calories":120}]',
          GateAPrefs.sleepSessionsJson: '[{"beginUnix":1,"endUnix":2}]',
          GateAPrefs.dailyHrJson:
              '[{"dayKey":"2026-08-01","minBpm":50,"avgBpm":60,"maxBpm":70,"sampleCount":1}]',
          GateAPrefs.swimSegmentParserVersion: 2,
          GateAPrefs.lastSyncCursor: 1700000000,
          GateAPrefs.gateAPassed: true,
          GateAPrefs.rememberedName: 'GT5',
          GateAPrefs.homeLastSyncStatus: 'ok',
          GateAPrefs.homeLastSyncAtMs: 1700000000000,
        },
        qwenInstalled: () async => true,
      );

      final envelope = await service.assembleEnvelope();

      expect(envelope['schemaVersion'], AppDataExportEnvelope.schemaVersion);
      expect(envelope['exportedAt'], '2026-08-05T12:00:00.000Z');
      expect(
        envelope['sensitivityNotes'],
        AppDataExportEnvelope.sensitivityNotes,
      );
      expect(envelope['consistencyClass'], 'best_effort');
      expect(envelope['knownOmissions'], isA<List>());

      final workouts = envelope['workouts'] as Map<String, dynamic>;
      expect(workouts['parseStatus'], 'ok');
      expect(workouts['items'], hasLength(1));

      final canonical = envelope['canonicalSwim'] as List;
      expect(canonical, hasLength(1));
      expect((canonical.first as Map)['parseStatus'], 'ok');

      final vitals = envelope['vitals'] as Map<String, dynamic>;
      expect((vitals['sleepSessions'] as Map)['items'], hasLength(1));
      expect((vitals['dailyHrSummaries'] as Map)['items'], hasLength(1));
      expect(vitals['hrSeries'], hasLength(1));

      final meta = envelope['meta'] as Map<String, dynamic>;
      expect(meta['swimSegmentParserVersion'], 2);
      expect(meta['lastSyncCursor'], 1700000000);
      expect(meta['gateAPassed'], isTrue);
      expect(meta['rememberedName'], 'GT5');
      expect(meta['qwenInstalled'], isTrue);
      expect(meta['homeLastSyncStatus'], 'ok');
      expect(meta.containsKey('rememberedMac'), isFalse);
      expect(meta.containsKey(GateAPrefs.geminiApiKey), isFalse);
    });

    test('empty stores → valid envelope with empty collections', () async {
      final service = await buildService();
      final envelope = await service.assembleEnvelope();

      expect(envelope['schemaVersion'], 1);
      expect((envelope['workouts'] as Map)['parseStatus'], 'absent');
      expect((envelope['workouts'] as Map)['items'], isEmpty);
      expect(envelope['canonicalSwim'], isEmpty);
      final vitals = envelope['vitals'] as Map<String, dynamic>;
      expect((vitals['sleepSessions'] as Map)['parseStatus'], 'absent');
      expect((vitals['hrSeries'] as List), isEmpty);
    });

    test('missing swim file listed in inventory; export succeeds', () async {
      final service = await buildService(
        prefsSeed: {
          GateAPrefs.workoutsJson:
              '[{"number":42,"startTime":1,"endTime":2,"durationSec":1,"type":6}]',
        },
      );
      final envelope = await service.assembleEnvelope();
      final inv =
          (envelope['meta'] as Map)['sideFileInventory'] as Map<String, dynamic>;
      expect(inv['missingCanonicalSwim'], contains(42));
      expect(envelope['canonicalSwim'], isEmpty);
    });

    test('orphan swim listed; body omitted from canonicalSwim', () async {
      await writeSwim(99, {
        'workoutNumber': 99,
        'startTime': 1,
        'secretShouldNotLeakViaOrphan': true,
      });
      final service = await buildService(
        prefsSeed: {
          GateAPrefs.workoutsJson:
              '[{"number":1,"startTime":1,"endTime":2,"durationSec":1,"type":6}]',
        },
      );
      final envelope = await service.assembleEnvelope();
      final inv =
          (envelope['meta'] as Map)['sideFileInventory'] as Map<String, dynamic>;
      expect(inv['orphanCanonicalSwim'], contains(99));
      final bodies = envelope['canonicalSwim'] as List;
      expect(bodies, isEmpty);
      final encoded = jsonEncode(envelope);
      expect(encoded.contains('secretShouldNotLeakViaOrphan'), isFalse);
    });

    test('corrupt workouts_json → parseStatus corrupt, not silent empty',
        () async {
      final service = await buildService(
        prefsSeed: {GateAPrefs.workoutsJson: '{not-json'},
      );
      final envelope = await service.assembleEnvelope();
      final workouts = envelope['workouts'] as Map<String, dynamic>;
      expect(workouts['parseStatus'], 'corrupt');
      expect(workouts['items'], isEmpty);
    });

    test('unreadable HR day skipped with parse error; others included',
        () async {
      await writeHrDay('2026-08-01', {
        'dayKey': '2026-08-01',
        'samples': [
          {'timestampUnix': 1, 'bpm': 60},
        ],
      });
      await writeHrDay('2026-08-02', '{broken');

      final service = await buildService(
        prefsSeed: {
          GateAPrefs.dailyHrJson:
              '[{"dayKey":"2026-08-01","minBpm":1,"avgBpm":1,"maxBpm":1,"sampleCount":1},'
              '{"dayKey":"2026-08-02","minBpm":1,"avgBpm":1,"maxBpm":1,"sampleCount":1}]',
        },
      );
      final envelope = await service.assembleEnvelope();
      final series = (envelope['vitals'] as Map)['hrSeries'] as List;
      expect(series, hasLength(1));
      expect((series.first as Map)['dayKey'], '2026-08-01');
      final inv =
          (envelope['meta'] as Map)['sideFileInventory'] as Map<String, dynamic>;
      expect(inv['parseErrors'], isNotEmpty);
    });

    test('option 2: dataPages/paceBlocks kept when present in raw prefs',
        () async {
      final service = await buildService(
        prefsSeed: {
          GateAPrefs.workoutsJson: jsonEncode([
            {
              'number': 7,
              'startTime': 1,
              'endTime': 2,
              'durationSec': 1,
              'type': 6,
              'dataPages': [
                {'page': 0},
              ],
              'paceBlocks': [
                {'pace': 90},
              ],
            },
          ]),
        },
      );
      final envelope = await service.assembleEnvelope();
      final item =
          ((envelope['workouts'] as Map)['items'] as List).first as Map;
      expect(item['dataPages'], isNotEmpty);
      expect(item['paceBlocks'], isNotEmpty);
      final omissions = (envelope['knownOmissions'] as List).cast<String>();
      expect(omissions, isNot(contains('swim_sample_data_pages')));
      expect(omissions, isNot(contains('swim_pace_blocks')));
    });

    test('option 2: absent optional streams remain in knownOmissions',
        () async {
      final service = await buildService(
        prefsSeed: {
          GateAPrefs.workoutsJson:
              '[{"number":1,"startTime":1,"endTime":2,"durationSec":1,"type":6}]',
        },
      );
      final envelope = await service.assembleEnvelope();
      final omissions = (envelope['knownOmissions'] as List).cast<String>();
      expect(omissions, contains('swim_sample_data_pages'));
      expect(omissions, contains('swim_pace_blocks'));
      expect(omissions, contains('ephemeral_coach_reasoner_outputs'));
      expect(omissions, contains('diagnosis_and_recommendation_snapshots'));
      expect(
        omissions,
        contains('daily_activity_calories_beyond_workout_totals_sum'),
      );
      expect(omissions, contains('gemini_api_key'));
      expect(omissions, contains('remembered_mac'));
      expect(omissions, contains('native_huawei_secrets'));
    });
  });

  group('U2 write / redact / busy / prune', () {
    test('write creates file; second export leaves only one matching file',
        () async {
      final service = await buildService(
        prefsSeed: {
          GateAPrefs.workoutsJson:
              '[{"number":1,"startTime":1,"endTime":2,"durationSec":1,"type":1}]',
        },
      );
      final first = await service.exportToCache();
      expect(first.isSuccess, isTrue);
      expect(first.file!.existsSync(), isTrue);

      // Advance clock via new service with later clock for distinct name,
      // then prune should leave one.
      SharedPreferences.setMockInitialValues({
        GateAPrefs.workoutsJson:
            '[{"number":1,"startTime":1,"endTime":2,"durationSec":1,"type":1}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final service2 = AppDataExportService(
        prefs: prefs,
        sideFileRootOverride: () => tempRoot,
        exportCacheRootOverride: () => tempRoot,
        isSyncInFlight: () => false,
        isVitalsSyncOrMergeInFlight: () => false,
        isForgetInFlight: () => false,
        isQwenInstalled: () async => false,
        clock: () => DateTime.utc(2026, 8, 5, 13, 0, 0),
      );
      final second = await service2.exportToCache();
      expect(second.isSuccess, isTrue);
      final cache = Directory(
        '${tempRoot.path}/${AppDataExportEnvelope.exportCacheDirName}',
      );
      final files = cache
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(files, hasLength(1));
      expect(files.single.path, second.file!.path);
    });

    test('sync busy → blocked; no file', () async {
      final service = await buildService(syncInFlight: () => true);
      final result = await service.exportToCache();
      expect(result.status, AppDataExportStatus.blocked);
      final cache = Directory(
        '${tempRoot.path}/${AppDataExportEnvelope.exportCacheDirName}',
      );
      expect(cache.existsSync() ? cache.listSync() : <File>[], isEmpty);
    });

    test('Forget-in-flight → blocked; no file', () async {
      final service = await buildService(forgetInFlight: () => true);
      final result = await service.exportToCache();
      expect(result.status, AppDataExportStatus.blocked);
    });

    test('busy flips true before write → fail; no share path', () async {
      var syncBusy = false;
      SharedPreferences.setMockInitialValues({
        GateAPrefs.workoutsJson:
            '[{"number":1,"startTime":1,"endTime":2,"durationSec":1,"type":1}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = AppDataExportService(
        prefs: prefs,
        sideFileRootOverride: () {
          // Flip busy during assemble (root lookup).
          syncBusy = true;
          return tempRoot;
        },
        exportCacheRootOverride: () => tempRoot,
        isSyncInFlight: () => syncBusy,
        isVitalsSyncOrMergeInFlight: () => false,
        isForgetInFlight: () => false,
        isQwenInstalled: () async => false,
        clock: () => DateTime.utc(2026, 8, 5, 12, 0, 0),
      );
      final result = await service.exportToCache();
      expect(result.status, AppDataExportStatus.blocked);
      expect(result.file, isNull);
    });

    test('gemini_api_key omitted; self-check passes', () async {
      final service = await buildService(
        prefsSeed: {
          GateAPrefs.geminiApiKey: 'sk-secret-test-key',
          GateAPrefs.workoutsJson:
              '[{"number":1,"startTime":1,"endTime":2,"durationSec":1,"type":1}]',
          GateAPrefs.rememberedName: 'GT5',
        },
      );
      final result = await service.exportToCache();
      expect(result.isSuccess, isTrue);
      final body = await result.file!.readAsString();
      expect(body.contains('sk-secret-test-key'), isFalse);
      expect(body.contains('"gemini_api_key":'), isFalse);
      expect(body.contains('GT5'), isTrue);
      expect(body.contains('"gemini_api_key"'), isTrue); // listed in knownOmissions
    });

    test('planted MAC in prefs field → omitted; export succeeds', () async {
      final service = await buildService(
        prefsSeed: {
          GateAPrefs.workoutsJson: jsonEncode([
            {
              'number': 1,
              'startTime': 1,
              'endTime': 2,
              'durationSec': 1,
              'type': 1,
              'note': 'AA:BB:CC:DD:EE:FF',
            },
          ]),
        },
      );
      final result = await service.exportToCache();
      expect(result.isSuccess, isTrue);
      final body = await result.file!.readAsString();
      expect(body.contains('AA:BB:CC:DD:EE:FF'), isFalse);
    });

    test('planted userId fails closed when still present as key', () async {
      // Forbidden key `userId` is stripped by redact; value-only 17-digit
      // in a non-forbidden field is also scrubbed.
      final service = await buildService(
        prefsSeed: {
          GateAPrefs.workoutsJson: jsonEncode([
            {
              'number': 1,
              'startTime': 1,
              'endTime': 2,
              'durationSec': 1,
              'type': 1,
              'label': '12345678901234567',
            },
          ]),
        },
      );
      final result = await service.exportToCache();
      expect(result.isSuccess, isTrue);
      final body = await result.file!.readAsString();
      expect(body.contains('12345678901234567'), isFalse);
    });

    test('Forget wipe prune removes export cache; swim orphans untouched',
        () async {
      final service = await buildService();
      final written = await service.exportToCache();
      expect(written.isSuccess, isTrue);

      final swimDir =
          Directory('${tempRoot.path}/${GateAPrefs.canonicalSwimDir}');
      await swimDir.create(recursive: true);
      final orphan = File('${swimDir.path}/swim_99.json');
      await orphan.writeAsString('{"workoutNumber":99}');

      await service.pruneExportCache();
      final cache = Directory(
        '${tempRoot.path}/${AppDataExportEnvelope.exportCacheDirName}',
      );
      expect(cache.existsSync(), isFalse);
      expect(orphan.existsSync(), isTrue);
    });
  });
}
