import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fitness_os/core/backend/backend_sync_telemetry.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SyncLedgerStore {
  Future<SyncLedgerData> load();

  Future<void> save(SyncLedgerData data);

  Future<T> withLock<T>(Future<T> Function() body);
}

class InMemorySyncLedgerStore implements SyncLedgerStore {
  SyncLedgerData _data = const SyncLedgerData();
  Future<void> _mutex = Future.value();

  @override
  Future<SyncLedgerData> load() async => _data;

  @override
  Future<void> save(SyncLedgerData data) async {
    final prev = _mutex;
    final completer = Completer<void>();
    _mutex = completer.future;
    await prev;
    _data = data;
    completer.complete();
  }

  @override
  Future<T> withLock<T>(Future<T> Function() body) => body();
}

class FileSyncLedgerStore implements SyncLedgerStore {
  FileSyncLedgerStore(
    this._rootDir, {
    DateTime Function()? now,
    SharedPreferences? prefs,
    BackendSyncTelemetry? telemetry,
  })  : _now = now ?? DateTime.now,
        _prefs = prefs,
        _telemetry = telemetry ?? NoOpBackendSyncTelemetry();

  final Future<Directory> Function() _rootDir;
  final DateTime Function() _now;
  final SharedPreferences? _prefs;
  final BackendSyncTelemetry _telemetry;

  Future<void> _writeMutex = Future.value();
  RandomAccessFile? _lockFile;

  static const _legacyLastSyncKey = 'backend_last_sync_ms';

  Future<File> _ledgerFile(Directory root) async =>
      File('${root.path}/sync/backend_ledger.json');

  Future<File> _bakFile(Directory root) async =>
      File('${root.path}/sync/backend_ledger.json.bak');

  Future<File> _tmpFile(Directory root) async =>
      File('${root.path}/sync/backend_ledger.json.tmp');

  Future<File> _lockFilePath(Directory root) async =>
      File('${root.path}/sync/backend_ledger.lock');

  @override
  Future<T> withLock<T>(Future<T> Function() body) async {
    final root = await _rootDir();
    await root.create(recursive: true);
    final lockPath = await _lockFilePath(root);
    if (!await lockPath.exists()) {
      await lockPath.create(recursive: true);
    }
    _lockFile = await lockPath.open(mode: FileMode.write);
    await _lockFile!.lock(FileLock.blockingExclusive);
    try {
      return await body();
    } finally {
      await _lockFile!.unlock();
      await _lockFile!.close();
      _lockFile = null;
    }
  }

  bool _watermarkValid(int? ms, DateTime now) {
    if (ms == null) return true;
    final minMs = DateTime(2020, 1, 1).millisecondsSinceEpoch;
    if (ms < minMs) return false;
    if (ms > now.millisecondsSinceEpoch + const Duration(minutes: 10).inMilliseconds) {
      return false;
    }
    return true;
  }

  SyncLedgerData? _parseEnvelope(String raw, DateTime now) {
    try {
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      final v = outer['v'];
      if (v != SyncLedgerData.schemaVersion) return null;
      final expectedSha = outer['sha256'] as String?;
      final dataMap = outer['data'] as Map<String, dynamic>?;
      if (dataMap == null || expectedSha == null) return null;
      final dataJson = jsonEncode(dataMap);
      final actualSha = sha256.convert(utf8.encode(dataJson)).toString();
      if (actualSha != expectedSha) return null;
      final data = SyncLedgerData.fromJson(dataMap);
      if (!_watermarkValid(data.lastSuccessfulSyncMs, now)) return null;
      if (!_watermarkValid(data.lastAckMs, now)) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<SyncLedgerData> _loadFile(File file, DateTime now) async {
    if (!await file.exists()) return const SyncLedgerData();
    final raw = await file.readAsString();
    return _parseEnvelope(raw, now) ?? const SyncLedgerData(fullResyncRequired: true);
  }

  Future<void> _migrateFromLegacyPrefs() async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (prefs.containsKey(_legacyLastSyncKey)) {
      await prefs.remove(_legacyLastSyncKey);
    }
  }

  Future<SyncLedgerData> _loadWithReason(DateTime now) async {
    final root = await _rootDir();
    await root.create(recursive: true);
    final main = await _ledgerFile(root);
    final bak = await _bakFile(root);

    if (!await main.exists()) {
      final legacy = _prefs?.getInt(_legacyLastSyncKey);
      if (legacy != null) {
        await _migrateFromLegacyPrefs();
        await _telemetry.ledgerReset('ledger_missing');
        return const SyncLedgerData(fullResyncRequired: true);
      }
      return const SyncLedgerData();
    }

    final raw = await main.readAsString();
    final parsed = _parseEnvelope(raw, now);
    if (parsed != null && !parsed.fullResyncRequired) {
      return parsed;
    }

    if (await bak.exists()) {
      final bakRaw = await bak.readAsString();
      final bakParsed = _parseEnvelope(bakRaw, now);
      if (bakParsed != null && !bakParsed.fullResyncRequired) {
        return bakParsed;
      }
    }

    final reason = parsed == null ? 'ledger_corrupt' : 'ledger_future';
    await _telemetry.ledgerReset(reason);
    return const SyncLedgerData(fullResyncRequired: true);
  }

  @override
  Future<SyncLedgerData> load() async {
    final now = _now();
    return _loadWithReason(now);
  }

  @override
  Future<void> save(SyncLedgerData data) async {
    final prev = _writeMutex;
    final completer = Completer<void>();
    _writeMutex = completer.future;
    await prev;
    try {
      final root = await _rootDir();
      await root.create(recursive: true);
      final main = await _ledgerFile(root);
      final bak = await _bakFile(root);
      final tmp = await _tmpFile(root);

      final dataJson = jsonEncode(data.toJson());
      final envelope = jsonEncode({
        'v': SyncLedgerData.schemaVersion,
        'sha256': sha256.convert(utf8.encode(dataJson)).toString(),
        'data': data.toJson(),
      });

      if (await main.exists()) {
        await main.copy(bak.path);
      }

      final sink = tmp.openWrite();
      sink.write(envelope);
      await sink.flush();
      await sink.close();
      if (await main.exists()) {
        await tmp.rename(main.path);
      } else {
        await tmp.rename(main.path);
      }
    } finally {
      completer.complete();
    }
  }
}