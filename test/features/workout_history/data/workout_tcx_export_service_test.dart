import 'dart:io';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/data/workout_tcx_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkoutTcxExportService', () {
    late Directory tempRoot;
    late bool forgetInFlight;
    late WorkoutTcxExportService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('tcx_export_test_');
      forgetInFlight = false;
      service = WorkoutTcxExportService(
        isForgetInFlight: () => forgetInFlight,
        exportCacheRootOverride: () => tempRoot,
      );
    });

    tearDown(() async {
      try {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      } catch (_) {}
    });

    const workout = WorkoutSummary(
      number: 7,
      startTime: 1700000000,
      endTime: 1700001200,
      durationSec: 1200,
      type: 6,
      distanceM: 1000,
      calories: 200,
    );

    test('writes TCX under cache and allows share path', () async {
      final result = await service.exportToCache(workout);
      expect(result.isSuccess, isTrue);
      expect(result.file, isNotNull);
      final file = result.file!;
      expect(await file.exists(), isTrue);
      expect(file.path, contains('/workout_tcx_exports/'));
      expect(file.path, endsWith('.tcx'));
      expect(service.isSharePathAllowed(file), isTrue);
      final body = await file.readAsString();
      expect(body, contains('Sport="Other"'));
      expect(body, contains('<DistanceMeters>1000</DistanceMeters>'));
      expect(body, contains('<Track>'));
      expect(body, contains('<DistanceMeters>1000.0</DistanceMeters>'));
    });

    test('blocks while Forget in flight', () async {
      forgetInFlight = true;
      final result = await service.exportToCache(workout);
      expect(result.status, WorkoutTcxExportStatus.blocked);
      expect(result.message, contains('Forget'));
    });

    test('refuses invalid workout timestamps', () async {
      const bad = WorkoutSummary(
        number: 1,
        startTime: 0,
        endTime: 0,
        durationSec: 0,
        type: 6,
      );
      final result = await service.exportToCache(bad);
      expect(result.status, WorkoutTcxExportStatus.failed);
    });

    test('pruneExportCache removes cache dir', () async {
      final result = await service.exportToCache(workout);
      expect(result.isSuccess, isTrue);
      final cache =
          Directory('${tempRoot.path}/${WorkoutTcxExportService.exportCacheDirName}');
      expect(await cache.exists(), isTrue);

      await service.pruneExportCache();
      expect(await cache.exists(), isFalse);
    });

    test('prunes prior TCX files on next export', () async {
      final first = await service.exportToCache(workout);
      expect(first.isSuccess, isTrue);

      const other = WorkoutSummary(
        number: 8,
        startTime: 1700005000,
        endTime: 1700005600,
        durationSec: 600,
        type: 2,
        distanceM: 5000,
      );
      final second = await service.exportToCache(other);
      expect(second.isSuccess, isTrue);

      final cache =
          Directory('${tempRoot.path}/${WorkoutTcxExportService.exportCacheDirName}');
      final files = await cache
          .list()
          .where((e) => e is File && e.path.endsWith('.tcx'))
          .toList();
      expect(files, hasLength(1));
      expect(files.single.path, second.file!.path);
    });
  });
}
