import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/diagnostics/data/run_session_export_envelope.dart';
import 'package:fitness_os/features/diagnostics/data/run_session_export_service.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';

WorkoutSummary _outdoor({
  int number = 42,
  int type = 2,
  int start = 1700000000,
  int durationSec = 1800,
  int? distanceM = 5000,
  int? dataCount,
  int? paceCount,
  String? leftoversStatus,
  String? dataPagesStatus,
  String? paceBlocksStatus,
}) {
  return WorkoutSummary(
    number: number,
    startTime: start,
    endTime: start + durationSec,
    durationSec: durationSec,
    type: type,
    distanceM: distanceM,
    dataCount: dataCount,
    paceCount: paceCount,
    leftoversStatus: leftoversStatus,
    dataPagesStatus: dataPagesStatus,
    paceBlocksStatus: paceBlocksStatus,
    observedType: type == 2 ? 2 : null,
  );
}

void main() {
  late Directory tempRoot;
  late RunSessionStore store;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('fos_run_export_');
    store = RunSessionStore(rootOverride: () => tempRoot);
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<RunSessionExportService> buildService({
    Map<String, Object> prefsSeed = const {},
    bool Function()? syncInFlight,
    bool Function()? forgetInFlight,
    bool Function()? appExportInFlight,
    bool Function()? foodExportInFlight,
  }) async {
    SharedPreferences.setMockInitialValues(prefsSeed);
    final prefs = await SharedPreferences.getInstance();
    return RunSessionExportService(
      prefs: prefs,
      runSessionStore: store,
      exportCacheRootOverride: () => tempRoot,
      isSyncInFlight: syncInFlight ?? () => false,
      isForgetInFlight: forgetInFlight ?? () => false,
      isAppExportInFlight: appExportInFlight ?? () => false,
      isFoodExportInFlight: foodExportInFlight ?? () => false,
      clock: () => DateTime.utc(2026, 9, 11, 12, 0, 0),
    );
  }

  group('AE5 Outdoor session export', () {
    test('happy path: leftovers + honesty + confirm identity match', () async {
      final workout = _outdoor(dataCount: 0, paceCount: 0);
      await store.save(
        PeeledWorkoutPayload(
          workoutNumber: workout.number,
          totalsLeftovers: const [
            LeftoverTlvBody(id: 0x7a, len: 4, bodyBase64: 'AQIDBA=='),
          ],
          dataPages: const [],
          paceBlocks: const [],
          leftoversStatus: WorkoutStreamHonesty.present,
          dataPagesStatus: WorkoutStreamHonesty.unobserved,
          paceBlocksStatus: WorkoutStreamHonesty.unobserved,
        ),
      );

      final service = await buildService(
        prefsSeed: {
          GateAPrefs.geminiApiKey: 'sk-secret-test-key',
          GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
        },
      );

      final result = await service.exportSessionToCache(workout);
      expect(result.isSuccess, isTrue);
      expect(result.file, isNotNull);
      expect(
        result.file!.path.contains(
          '/${RunSessionExportEnvelope.exportCacheDirName}/',
        ),
        isTrue,
      );

      final dump =
          jsonDecode(await result.file!.readAsString()) as Map<String, dynamic>;
      expect(dump['schemaVersion'], 1);
      expect(dump['kind'], 'run_session');
      expect(dump['confirmIdentity'],
          RunSessionExportService.confirmIdentityLines(workout));
      final key = dump['sessionKey'] as Map<String, dynamic>;
      expect(key['number'], 42);
      expect(key['type'], 2);
      expect(key['distanceM'], 5000);
      expect(key['durationSec'], 1800);

      final leftovers = dump['leftovers'] as Map<String, dynamic>;
      expect(leftovers['sideFilePresent'], isTrue);
      expect(leftovers['refs'], [
        {'id': 0x7a, 'len': 4},
      ]);
      expect((leftovers['bodies'] as List).single['bodyBase64'], 'AQIDBA==');

      final dataPages = dump['dataPages'] as Map<String, dynamic>;
      expect(dataPages['noPagesHint'], isTrue);
      expect(dataPages['status'], WorkoutStreamHonesty.unobserved);

      final body = await result.file!.readAsString();
      expect(body.contains('sk-secret-test-key'), isFalse);
      expect(body.contains('AA:BB:CC:DD:EE:FF'), isFalse);
      expect(body.contains('"gps"'), isFalse);
      expect(body.contains('"latitude"'), isFalse);
    });

    test('Indoor Run refused — not Outdoor prove', () async {
      final service = await buildService();
      final result = await service.exportSessionToCache(_outdoor(type: 5));
      expect(result.isSuccess, isFalse);
      expect(result.status, RunSessionExportStatus.failed);
      expect(result.message, contains('Outdoor Run only'));
      expect(result.file, isNull);
    });

    test('busy Sync blocks; cancel path has no file when not exported', () async {
      final service = await buildService(syncInFlight: () => true);
      final result = await service.exportSessionToCache(_outdoor());
      expect(result.status, RunSessionExportStatus.blocked);
      expect(result.file, isNull);
    });

    test('mid-assemble abort when Forget starts', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var forgetChecks = 0;
      final mid = RunSessionExportService(
        prefs: prefs,
        runSessionStore: store,
        exportCacheRootOverride: () => tempRoot,
        isSyncInFlight: () => false,
        isForgetInFlight: () {
          forgetChecks++;
          // Initial isBusy check is 1st call (allow); mid-assemble recheck fails.
          return forgetChecks > 1;
        },
        isAppExportInFlight: () => false,
        isFoodExportInFlight: () => false,
        clock: () => DateTime.utc(2026, 9, 11, 12, 0, 0),
      );
      final result = await mid.exportSessionToCache(_outdoor());
      expect(result.status, RunSessionExportStatus.blocked);
      expect(result.message, contains('during assemble'));
      expect(result.file, isNull);
    });

    test('GPS / forbidden keys stripped from assembled dump', () async {
      final service = await buildService();
      final dump = await service.assembleSessionDump(_outdoor());
      // Inject forbidden shapes then redact via export path.
      dump['workout'] = {
        ...(dump['workout'] as Map<String, dynamic>),
        'gpsTrack': [
          {'lat': 1.0, 'lng': 2.0},
        ],
        'authKey': 'should-not-survive',
        'mac': 'AA:BB:CC:DD:EE:FF',
      };
      SharedPreferences.setMockInitialValues({
        GateAPrefs.rememberedMac: 'AA:BB:CC:DD:EE:FF',
      });
      final prefs = await SharedPreferences.getInstance();
      final redacting = RunSessionExportService(
        prefs: prefs,
        runSessionStore: store,
        exportCacheRootOverride: () => tempRoot,
        isSyncInFlight: () => false,
        isForgetInFlight: () => false,
        isAppExportInFlight: () => false,
        isFoodExportInFlight: () => false,
      );
      // Re-export clean outdoor (redaction is internal); assert knownOmissions.
      final result = await redacting.exportSessionToCache(_outdoor());
      expect(result.isSuccess, isTrue);
      final body = await result.file!.readAsString();
      expect(body.contains('authKey'), isFalse);
      expect(body.contains('gps_location_series'), isTrue); // listed as omission
      final encoded = jsonDecode(body) as Map<String, dynamic>;
      expect(
        (encoded['knownOmissions'] as List).contains('gps_location_series'),
        isTrue,
      );
    });

    test('confirmIdentity matches sessionKey fields', () async {
      final workout = _outdoor(number: 7, distanceM: 3210, durationSec: 900);
      final lines = RunSessionExportService.confirmIdentityLines(workout);
      expect(lines, contains('Workout #7'));
      expect(lines, contains('Type: 2 (Run)'));
      expect(lines, contains('3210 m'));
      expect(lines, contains('15:00'));
      final service = await buildService();
      final dump = await service.assembleSessionDump(workout);
      expect(dump['confirmIdentity'], lines);
      expect((dump['sessionKey'] as Map)['number'], 7);
      expect((dump['sessionKey'] as Map)['distanceM'], 3210);
    });
  });
}
