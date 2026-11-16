import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/strength_session_export_service.dart';
import 'package:fitness_os/features/workout_history/data/workout_leftover_store.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

class _FakeRepo implements WorkoutHistoryRepository {
  _FakeRepo({
    required this.workouts,
    this.syncOrMergeInFlight = false,
  });

  List<WorkoutSummary> workouts;
  bool syncOrMergeInFlight;

  @override
  Future<bool> isGateAPassed() async => true;

  @override
  Future<List<WorkoutSummary>> loadLocal() async => List.of(workouts);

  @override
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch({
    bool forceFullHistory = false,
  }) async =>
      Right(workouts);

  @override
  bool get isSyncOrMergeInFlight => syncOrMergeInFlight;

  @override
  bool get lastLeftoverPersistLanded => true;

  @override
  Future<void> clearLocal() async {
    workouts = [];
  }

  @override
  Future<CanonicalSwimSession?> loadCanonicalSwim(int workoutNumber) async =>
      null;

  @override
  CanonicalSwimSession? canonicalSwimFromSummary(WorkoutSummary workout) =>
      null;

  @override
  Future<List<CanonicalSwimSession>> loadAllCanonicalSwims() async =>
      const [];

  @override
  Future<SwimDiagnosisReport> loadSwimDiagnosisReport({
    int? focusWorkoutNumber,
  }) async =>
      const SwimDiagnosisReport(
        sessionDiagnoses: [],
        trendDiagnoses: [],
        trends: SwimTrends(points: [], sessionCount: 0),
      );
}

WorkoutSummary _strength({
  required int number,
  required int startTime,
  int durationSec = 1800,
  int? calories,
  int? dataCount,
  int? sampleCount,
  String? sampleFetch,
  String? leftoverPath,
  int? leftoverLen,
  bool? leftoverPresent,
  String? samplePath,
  int? load,
  int? recoveryTime,
}) {
  return WorkoutSummary(
    number: number,
    startTime: startTime,
    endTime: startTime + durationSec,
    durationSec: durationSec,
    type: 140,
    calories: calories,
    dataCount: dataCount,
    sampleCount: sampleCount,
    sampleFetch: sampleFetch,
    leftoverPath: leftoverPath,
    leftoverLen: leftoverLen,
    leftoverPresent: leftoverPresent,
    samplePath: samplePath,
    load: load,
    recoveryTime: recoveryTime,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory rootDir;
  late WorkoutLeftoverStore leftoverStore;
  late _FakeRepo repo;
  late StrengthSessionExportService exportService;
  late bool forgetInFlight;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('strength_export_test');
    rootDir = Directory('${tempDir.path}/app_support');
    await rootDir.create(recursive: true);

    leftoverStore = WorkoutLeftoverStore(rootOverride: () => rootDir);
    forgetInFlight = false;
    repo = _FakeRepo(workouts: []);
    exportService = StrengthSessionExportService(
      repository: repo,
      leftoverStore: leftoverStore,
      isForgetInFlight: () => forgetInFlight,
      isSyncOrMergeInFlight: () => repo.syncOrMergeInFlight,
      sideFileRootOverride: () => rootDir,
      exportCacheRootOverride: () => tempDir,
      clock: () => DateTime.utc(2026, 9, 10, 12, 0, 0),
    );
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<Map<String, dynamic>> readEnvelope(File file) async {
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  group('StrengthSessionExportService', () {
    test('exports one opened session with leftover bytes (AE3)', () async {
      const number = 34;
      const start = 1723400000;
      final leftover = Uint8List.fromList([0x66, 0x00, 0x04, 1, 2, 3, 4]);
      final path = await leftoverStore.save(
        workoutNumber: number,
        startTime: start,
        bytes: leftover,
      );

      repo.workouts = [
        _strength(
          number: number,
          startTime: start,
          calories: 220,
          load: 42,
          leftoverPath: path,
          leftoverLen: leftover.length,
          leftoverPresent: true,
          dataCount: 0,
          sampleFetch: 'none',
        ),
        _strength(
          number: 99,
          startTime: start + 10000,
          calories: 100,
          dataCount: 0,
          sampleFetch: 'none',
        ),
      ];

      final result = await exportService.exportSessionToCache(number);

      expect(result.isSuccess, isTrue);
      expect(result.file!.path, contains('strength_session_exports'));
      expect(result.file!.path, contains('strength_session_34_'));

      final envelope = await readEnvelope(result.file!);
      expect(envelope['schemaVersion'], 1);
      expect(envelope['kind'], 'strength_session');
      expect(envelope['sessions'], hasLength(1));

      final session = envelope['sessions'][0] as Map<String, dynamic>;
      expect(session['number'], 34);
      expect(session['calories'], 220);
      expect(session['load'], 42);
      expect(session.containsKey('zoneMinutes'), isFalse);
      expect(session.containsKey('recoveryPercent'), isFalse);
      expect(session.containsKey('remembered_mac'), isFalse);
      expect(session.containsKey('userId'), isFalse);
      expect(session.containsKey(GateAPrefs.geminiApiKey), isFalse);

      final leftoverOut = session['leftover'] as Map<String, dynamic>;
      expect(leftoverOut['present'], isTrue);
      expect(leftoverOut['len'], leftover.length);
      expect(
        base64Decode(leftoverOut['bytesBase64'] as String),
        leftover,
      );

      final samples = session['samples'] as Map<String, dynamic>;
      expect(samples['sampleFetch'], 'none');
      expect(samples['present'], isFalse);
    });

    test('dumps opened number only when two strength sessions exist', () async {
      repo.workouts = [
        _strength(number: 10, startTime: 100, calories: 10),
        _strength(number: 20, startTime: 200, calories: 20),
      ];

      final result = await exportService.exportSessionToCache(20);
      expect(result.isSuccess, isTrue);
      final envelope = await readEnvelope(result.file!);
      final session = envelope['sessions'][0] as Map<String, dynamic>;
      expect(session['number'], 20);
      expect(session['calories'], 20);
      expect(envelope['sessions'], hasLength(1));
    });

    test('AE5: points persisted → dump contains points bytes', () async {
      const number = 55;
      const start = 1723500000;
      final sampleBytes = Uint8List.fromList([0x81, 0x00, 0x05, 9, 8, 7, 6, 5]);
      final sampleRel =
          '${GateAPrefs.workoutHrSamplesDir}/${number}_$start.bin';
      final sampleFile = File('${rootDir.path}/$sampleRel');
      await sampleFile.parent.create(recursive: true);
      await sampleFile.writeAsBytes(sampleBytes);

      repo.workouts = [
        _strength(
          number: number,
          startTime: start,
          dataCount: 2,
          sampleCount: 40,
          sampleFetch: 'ok',
          samplePath: sampleRel,
        ),
      ];

      final result = await exportService.exportSessionToCache(number);
      expect(result.isSuccess, isTrue);
      final session =
          (await readEnvelope(result.file!))['sessions'][0] as Map<String, dynamic>;
      expect(session.containsKey('zoneMinutes'), isFalse);
      final samples = session['samples'] as Map<String, dynamic>;
      expect(samples['present'], isTrue);
      expect(samples['sampleFetch'], 'ok');
      expect(
        base64Decode(samples['pointsBytesBase64'] as String),
        sampleBytes,
      );
    });

    test('AE2 via dump flags: sampleFetch=none when Count said no pages',
        () async {
      repo.workouts = [
        _strength(
          number: 1,
          startTime: 1,
          dataCount: 0,
          sampleFetch: 'none',
        ),
      ];

      final result = await exportService.exportSessionToCache(1);
      final session =
          (await readEnvelope(result.file!))['sessions'][0] as Map<String, dynamic>;
      final samples = session['samples'] as Map<String, dynamic>;
      expect(samples['sampleFetch'], 'none');
      expect(samples['present'], isFalse);
      expect(samples.containsKey('points'), isFalse);
      expect(session['sampleFetch'], 'none');
    });

    test('session gone after Forget → no file', () async {
      repo.workouts = [];
      final result = await exportService.exportSessionToCache(34);
      expect(result.isSuccess, isFalse);
      expect(result.status, StrengthSessionExportStatus.failed);
      expect(result.message, contains('no longer on this device'));
      expect(result.file, isNull);
      final cache = Directory('${tempDir.path}/strength_session_exports');
      if (await cache.exists()) {
        expect(await cache.list().isEmpty, isTrue);
      }
    });

    test('blocks when Forget is in flight', () async {
      repo.workouts = [_strength(number: 1, startTime: 1)];
      forgetInFlight = true;
      final result = await exportService.exportSessionToCache(1);
      expect(result.status, StrengthSessionExportStatus.blocked);
      expect(result.message, contains('Forget'));
      expect(result.file, isNull);
    });

    test('blocks when Sync or merge is in flight', () async {
      repo.workouts = [_strength(number: 1, startTime: 1)];
      repo.syncOrMergeInFlight = true;
      final result = await exportService.exportSessionToCache(1);
      expect(result.status, StrengthSessionExportStatus.blocked);
      expect(result.message, contains('sync'));
      expect(result.file, isNull);
    });

    test('all-sessions exports only type=140 rows', () async {
      repo.workouts = [
        WorkoutSummary(
          number: 6,
          startTime: 10,
          endTime: 100,
          durationSec: 90,
          type: 6,
          calories: 50,
        ),
        _strength(number: 34, startTime: 200, calories: 220),
        _strength(number: 35, startTime: 300, calories: 180),
      ];

      final result = await exportService.exportAllStrengthSessionsToCache();
      expect(result.isSuccess, isTrue);
      final envelope = await readEnvelope(result.file!);
      expect(envelope['kind'], 'strength_sessions');
      expect(envelope['sessionCount'], 2);
      expect(envelope['sessions'], hasLength(2));
      final numbers = (envelope['sessions'] as List)
          .map((e) => (e as Map)['number'])
          .toList();
      expect(numbers, containsAll([34, 35]));
      expect(numbers, isNot(contains(6)));
    });

    test('assembled JSON omits remembered MAC / secrets', () async {
      repo.workouts = [
        _strength(number: 1, startTime: 1, recoveryTime: 3600),
      ];
      final result = await exportService.exportSessionToCache(1);
      final raw = await result.file!.readAsString();
      expect(raw.contains('remembered_mac'), isFalse);
      expect(raw.contains('AA:BB:CC'), isFalse);
      expect(raw.contains('gemini'), isFalse);
      expect(raw.contains('userId'), isFalse);
      final session =
          (await readEnvelope(result.file!))['sessions'][0] as Map<String, dynamic>;
      expect(session['recoveryTime'], 3600);
      expect(session.containsKey('recoveryPercent'), isFalse);
    });

    test('pruneStrengthExportCache deletes cache directory', () async {
      final cacheDir = Directory('${tempDir.path}/strength_session_exports');
      await cacheDir.create(recursive: true);
      final file = File('${cacheDir.path}/old.json');
      await file.writeAsString('{}');

      await exportService.pruneStrengthExportCache();

      expect(await cacheDir.exists(), isFalse);
    });

    test('exportInFlight clears after completion', () async {
      repo.workouts = [_strength(number: 1, startTime: 1)];
      expect(exportService.exportInFlight, isFalse);
      await exportService.exportSessionToCache(1);
      expect(exportService.exportInFlight, isFalse);
    });

    test('prunes prior exports after successful export', () async {
      repo.workouts = [_strength(number: 1, startTime: 1)];
      final cacheDir = Directory('${tempDir.path}/strength_session_exports');
      await cacheDir.create(recursive: true);
      final prior = File('${cacheDir.path}/prior.json');
      await prior.writeAsString('old');

      final result = await exportService.exportSessionToCache(1);
      expect(result.isSuccess, isTrue);
      expect(await prior.exists(), isFalse);
      expect(await result.file!.exists(), isTrue);
    });
  });
}
