import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fitness_os/core/backend/backend_sync_telemetry.dart';
import 'package:fitness_os/core/backend/sync_ledger_store.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/backend_fakes.dart';

Future<void> _writeEnvelope(File file, SyncLedgerData data) async {
  final dataJson = jsonEncode(data.toJson());
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode({
    'v': SyncLedgerData.schemaVersion,
    'sha256': sha256.convert(utf8.encode(dataJson)).toString(),
    'data': data.toJson(),
  }));
}

void main() {
  test('in-memory round-trip', () async {
    final store = InMemorySyncLedgerStore();
    const data = SyncLedgerData(lastSuccessfulSyncMs: 1700000000000);
    await store.save(data);
    final loaded = await store.load();
    expect(loaded.lastSuccessfulSyncMs, 1700000000000);
  });

  group('FileSyncLedgerStore', () {
    late Directory root;
    late RecordingTelemetry telemetry;

    FileSyncLedgerStore store({DateTime Function()? now, SharedPreferences? prefs}) {
      return FileSyncLedgerStore(
        () async => root,
        now: now,
        prefs: prefs,
        telemetry: telemetry,
      );
    }

    setUp(() async {
      root = await Directory.systemTemp.createTemp('ledger_test_');
      telemetry = RecordingTelemetry();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('round-trip and leaves .bak after save', () async {
      final s = store();
      const data = SyncLedgerData(lastSuccessfulSyncMs: 1700000000000);
      await s.save(data);
      await s.save(
        data.copyWith(lastSuccessfulSyncMs: 1700000010000),
      );
      final loaded = await s.load();
      expect(loaded.lastSuccessfulSyncMs, 1700000010000);
      expect(
        await File('${root.path}/sync/backend_ledger.json.bak').exists(),
        isTrue,
      );
    });

    test('corrupt main falls back to .bak', () async {
      final s = store();
      await s.save(const SyncLedgerData(lastSuccessfulSyncMs: 1700000000000));
      await s.save(
        const SyncLedgerData(lastSuccessfulSyncMs: 1700000010000),
      );
      final main = File('${root.path}/sync/backend_ledger.json');
      await main.writeAsString('not-json');

      final loaded = await s.load();
      expect(loaded.lastSuccessfulSyncMs, 1700000000000);
    });

    test('both corrupt → fullResyncRequired + breadcrumb', () async {
      final s = store();
      await s.save(const SyncLedgerData(lastSuccessfulSyncMs: 1700000000000));
      final main = File('${root.path}/sync/backend_ledger.json');
      final bak = File('${root.path}/sync/backend_ledger.json.bak');
      await main.writeAsString('{bad');
      await bak.writeAsString('{also-bad');

      final loaded = await s.load();
      expect(loaded.fullResyncRequired, isTrue);
      expect(
        telemetry.breadcrumbs.any((b) => b.$2['reason'] != null),
        isTrue,
      );
    });

    test('sha mismatch on main uses bak', () async {
      final s = store();
      await s.save(const SyncLedgerData(lastSuccessfulSyncMs: 1700000000000));
      await s.save(
        const SyncLedgerData(lastSuccessfulSyncMs: 1700000010000),
      );
      final main = File('${root.path}/sync/backend_ledger.json');
      final outer = jsonDecode(await main.readAsString()) as Map<String, dynamic>;
      outer['sha256'] = '0' * 64;
      await main.writeAsString(jsonEncode(outer));

      final loaded = await s.load();
      expect(loaded.lastSuccessfulSyncMs, 1700000000000);
    });

    test('future watermark → reset', () async {
      final now = DateTime(2026, 6, 1);
      final futureMs =
          now.add(const Duration(days: 2)).millisecondsSinceEpoch;
      final main = File('${root.path}/sync/backend_ledger.json');
      await _writeEnvelope(
        main,
        SyncLedgerData(lastSuccessfulSyncMs: futureMs),
      );

      final loaded = await store(now: () => now).load();
      expect(loaded.fullResyncRequired, isTrue);
    });

    test('watermark before 2020 → reset', () async {
      final now = DateTime(2026, 6, 1);
      final main = File('${root.path}/sync/backend_ledger.json');
      await _writeEnvelope(
        main,
        const SyncLedgerData(lastSuccessfulSyncMs: 1000),
      );

      final loaded = await store(now: () => now).load();
      expect(loaded.fullResyncRequired, isTrue);
    });

    test('migration removes backend_last_sync_ms', () async {
      SharedPreferences.setMockInitialValues({
        'backend_last_sync_ms': 999,
      });
      final prefs = await SharedPreferences.getInstance();
      final loaded = await store(prefs: prefs).load();
      expect(loaded.fullResyncRequired, isTrue);
      expect(prefs.containsKey('backend_last_sync_ms'), isFalse);
    });

    test('withLock runs bodies serially', () async {
      final s = store();
      final order = <int>[];
      await s.withLock(() async {
        order.add(1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add(2);
      });
      await s.withLock(() async {
        order.add(3);
      });
      expect(order, [1, 2, 3]);
    });
  });
}