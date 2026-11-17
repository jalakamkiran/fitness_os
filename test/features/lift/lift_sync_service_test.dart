import 'package:dio/dio.dart';
import 'package:fitness_os/features/lift/data/lift_store.dart';
import 'package:fitness_os/features/lift/data/lift_sync_service.dart';
import 'package:fitness_os/features/lift/domain/strength_set.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('removes pending ids on 200', () async {
    final root = await Directory.systemTemp.createTemp('lift_sync');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final store = LiftStore(rootOverride: () => root);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'synced': 1},
            ),
          );
        },
      ),
    );

    const set = StrengthSet(
      id: 'ps_bench_1',
      sessionId: 'ps',
      exerciseId: 'bench',
      exercise: 'Bench',
      setIndex: 1,
      plannedKg: 60,
      plannedReps: 8,
      actualKg: 60,
      actualReps: 8,
      failed: false,
      notifiedAtMs: 1,
      loggedAtMs: 2,
      source: 'watch_reply',
    );
    await store.upsertStrengthSet(set);

    final service = LiftSyncService(
      store: store,
      dio: dio,
      debugForceSync: true,
    );
    final n = await service.syncPending();
    expect(n, 1);
    expect(await store.loadPendingUploadIds(), isEmpty);
  });
}