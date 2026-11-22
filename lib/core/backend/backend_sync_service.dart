import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:fitness_os/core/backend/backend_config.dart';
import 'package:fitness_os/core/backend/backend_sync_telemetry.dart';
import 'package:fitness_os/core/backend/backend_transport.dart';
import 'package:fitness_os/core/backend/local_sync_snapshot.dart';
import 'package:fitness_os/core/backend/sync_ledger_store.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/core/backend/sync_record_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class BackendPusher {
  Future<PushOutcome> push(SyncTrigger trigger);

  void startRetryTimer() {}

  void stopRetryTimer() {}
}

class BackendSyncService implements BackendPusher {
  BackendSyncService({
    required BackendTransport transport,
    required SyncLedgerStore ledger,
    required LocalSyncSnapshot snapshot,
    required SyncRecordValidator validator,
    required SharedPreferences prefs,
    DateTime Function()? now,
    Random? random,
    BackendSyncTelemetry? telemetry,
    bool Function()? isEnabled,
    int maxRecordsPerChunk = 150,
    int maxChunkBytes = 200 * 1024,
  })  : _transport = transport,
        _ledger = ledger,
        _snapshot = snapshot,
        _validator = validator,
        _prefs = prefs,
        _now = now ?? DateTime.now,
        _random = random ?? Random(),
        _telemetry = telemetry ?? NoOpBackendSyncTelemetry(),
        _isEnabled = isEnabled ?? (() => BackendConfig.isEnabled),
        _maxRecordsPerChunk = maxRecordsPerChunk,
        _maxChunkBytes = maxChunkBytes;

  final BackendTransport _transport;
  final SyncLedgerStore _ledger;
  final LocalSyncSnapshot _snapshot;
  final SyncRecordValidator _validator;
  final SharedPreferences _prefs;
  final DateTime Function() _now;
  final Random _random;
  final BackendSyncTelemetry _telemetry;
  final bool Function() _isEnabled;
  final int _maxRecordsPerChunk;
  final int _maxChunkBytes;

  static const _legacyLastSyncKey = 'backend_last_sync_ms';

  final ValueNotifier<BackendSyncStatus> _status =
      ValueNotifier(const BackendSyncStatus());

  ValueListenable<BackendSyncStatus> get status => _status;

  bool _inFlight = false;
  bool _followUpQueued = false;
  SyncTrigger _followUpTrigger = SyncTrigger.retry;
  Timer? _retryTimer;
  final Set<String> _quarantineReported = {};

  @override
  Future<PushOutcome> push(SyncTrigger trigger) async {
    if (!_isEnabled()) {
      return PushOutcome(trigger: trigger, ok: false, skippedDisabled: true);
    }

    if (_inFlight) {
      if (trigger.priority > _followUpTrigger.priority) {
        _followUpTrigger = trigger;
      }
      _followUpQueued = true;
      return PushOutcome(trigger: trigger, ok: false, queued: true);
    }

    final nowMs = _now().millisecondsSinceEpoch;
    final ledgerProbe = await _ledger.load();
    if ((trigger == SyncTrigger.retry || trigger == SyncTrigger.background) &&
        ledgerProbe.nextRetryAtMs != null &&
        nowMs < ledgerProbe.nextRetryAtMs!) {
      return PushOutcome(trigger: trigger, ok: false);
    }

    _inFlight = true;
    _emitStatus(inFlight: true);
    await _telemetry.breadcrumb(trigger.breadcrumbStage);

    var outcome = PushOutcome(trigger: trigger, ok: false);
    try {
      outcome = await _ledger.withLock(() => _pushLocked(trigger));
    } finally {
      _inFlight = false;
      _emitStatus(inFlight: false);
      if (_followUpQueued) {
        _followUpQueued = false;
        final next = _followUpTrigger;
        _followUpTrigger = SyncTrigger.retry;
        unawaited(push(next));
      }
    }
    return outcome;
  }

  Future<PushOutcome> _pushLocked(SyncTrigger trigger) async {
    var ledger = await _ledger.load();
    final records = await _snapshot.build();
    if (records == null) {
      _followUpQueued = true;
      if (trigger.priority > _followUpTrigger.priority) {
        _followUpTrigger = trigger;
      }
      return PushOutcome(trigger: trigger, ok: false, queued: true);
    }

    final nowMs = _now().millisecondsSinceEpoch;
    final now = _now();
    final pendingRecords = <SyncRecord>[];
    final entries = Map<String, LedgerEntry>.from(ledger.entries);

    for (final r in records) {
      final existing = entries[r.ledgerKey];
      final needsPending = ledger.fullResyncRequired ||
          existing == null ||
          existing.state == LedgerState.pending ||
          existing.hash != r.contentHash;
      if (!needsPending) continue;
      if (existing?.state == LedgerState.quarantined &&
          existing!.hash == r.contentHash) {
        continue;
      }
      final validation = _validator.validate(r, now: now);
      if (!validation.ok) {
        entries[r.ledgerKey] = LedgerEntry(
          state: LedgerState.quarantined,
          hash: r.contentHash,
          updatedAtMs: nowMs,
          reason: validation.reason,
        );
        await _reportQuarantine(r, validation.reason!);
        continue;
      }
      entries[r.ledgerKey] = LedgerEntry(
        state: LedgerState.pending,
        hash: r.contentHash,
        updatedAtMs: nowMs,
        attempts: existing?.attempts ?? 0,
      );
      pendingRecords.add(r);
    }

    ledger = ledger.copyWith(entries: entries);
    await _ledger.save(ledger);

    if (pendingRecords.isEmpty) {
      ledger = ledger.copyWith(
        lastSuccessfulSyncMs: nowMs,
        fullResyncRequired: false,
        clearNextRetryAtMs: true,
        consecutiveFailures: 0,
      );
      await _ledger.save(ledger);
      _emitStatusFromLedger(ledger);
      return PushOutcome(trigger: trigger, ok: true);
    }

    final ordered = _sortPending(pendingRecords);
    final chunks = _buildChunks(ordered, nowMs);
    var attempted = 0;
    var accepted = 0;
    var rejected = 0;
    var quarantined = 0;
    var ok = true;
    int? lastHttp;

    for (var i = 0; i < chunks.length; i++) {
      final chunkRecords = chunks[i];
      attempted += chunkRecords.length;
      final sendResult = await _postChunk(
        chunkRecords,
        chunkIndex: i,
        chunkCount: chunks.length,
        nowMs: nowMs,
      );
      lastHttp = sendResult.status;

      if (sendResult.status == 200) {
        final json = sendResult.json;
        if (json != null && json.containsKey('accepted')) {
          final ackIds = _collectAcceptedIds(json);
          final rejectedList = (json['rejected'] as List?) ?? [];
          for (final r in chunkRecords) {
            if (ackIds.contains(r.id)) {
              entries[r.ledgerKey] = LedgerEntry(
                state: LedgerState.synced,
                hash: r.contentHash,
                updatedAtMs: nowMs,
                ackedAtMs: nowMs,
                attempts: 0,
              );
              accepted++;
            }
          }
          for (final rej in rejectedList) {
            if (rej is! Map) continue;
            final id = rej['id'] as String?;
            final reason = rej['reason'] as String? ?? 'unknown';
            final kind = rej['kind'] as String?;
            if (id == null) continue;
            final key = kind != null ? '$kind:$id' : _findKeyById(entries, id);
            if (key != null) {
              entries[key] = LedgerEntry(
                state: LedgerState.quarantined,
                hash: entries[key]?.hash ?? '',
                updatedAtMs: nowMs,
                reason: 'server_$reason',
              );
              rejected++;
              quarantined++;
            }
          }
          for (final r in chunkRecords) {
            final e = entries[r.ledgerKey];
            if (e?.state != LedgerState.synced &&
                e?.state != LedgerState.quarantined) {
              entries[r.ledgerKey] = e!.copyWith(attempts: e.attempts + 1);
            }
          }
        } else {
          for (final r in chunkRecords) {
            entries[r.ledgerKey] = LedgerEntry(
              state: LedgerState.synced,
              hash: r.contentHash,
              updatedAtMs: nowMs,
              ackedAtMs: nowMs,
              attempts: 0,
            );
          }
          accepted += chunkRecords.length;
        }
        ledger = ledger.copyWith(entries: entries, lastAckMs: nowMs);
        await _ledger.save(ledger);
      } else if (sendResult.status == 400 &&
          sendResult.json?['error'] == 'checksum_mismatch') {
        final retry = await _postChunk(
          chunkRecords,
          chunkIndex: i,
          chunkCount: chunks.length,
          nowMs: nowMs,
        );
        if (retry.status != 200) {
          ok = false;
          _incrementPendingAttempts(entries, chunkRecords);
          break;
        }
      } else if (sendResult.status == 413) {
        if (chunkRecords.length <= 1) {
          final r = chunkRecords.first;
          entries[r.ledgerKey] = LedgerEntry(
            state: LedgerState.quarantined,
            hash: r.contentHash,
            updatedAtMs: nowMs,
            reason: 'too_large',
          );
          quarantined++;
        } else {
          final mid = chunkRecords.length ~/ 2;
          final first = chunkRecords.sublist(0, mid);
          final second = chunkRecords.sublist(mid);
          i--;
          chunks.insert(i + 1, second);
          chunks[i] = first;
          continue;
        }
      } else if (sendResult.status == 401 || sendResult.status == 403) {
        ok = false;
        _incrementPendingAttempts(entries, chunkRecords);
        ledger = ledger.copyWith(
          entries: entries,
          consecutiveFailures: ledger.consecutiveFailures + 1,
          nextRetryAtMs: nowMs + const Duration(minutes: 30).inMilliseconds,
        );
        await _ledger.save(ledger);
        _status.value = _status.value.copyWith(lastError: 'auth');
        break;
      } else {
        ok = false;
        _incrementPendingAttempts(entries, chunkRecords);
        break;
      }
    }

    ledger = ledger.copyWith(entries: entries);
    final stillPending =
        entries.values.where((e) => e.state == LedgerState.pending).length;

    if (ok && stillPending == 0) {
      ledger = ledger.copyWith(
        lastSuccessfulSyncMs: nowMs,
        consecutiveFailures: 0,
        clearNextRetryAtMs: true,
        fullResyncRequired: false,
      );
    } else if (!ok || stillPending > 0) {
      final failures = ledger.consecutiveFailures + 1;
      final backoffMs = _backoffMs(failures);
      ledger = ledger.copyWith(
        consecutiveFailures: failures,
        nextRetryAtMs: nowMs + backoffMs,
      );
      await _telemetry.breadcrumb('retry', data: {'durationMs': backoffMs});
      _scheduleRetryTimer(backoffMs);
    }

    await _ledger.save(ledger);
    _emitStatusFromLedger(ledger);

    return PushOutcome(
      trigger: trigger,
      ok: ok && stillPending == 0,
      attempted: attempted,
      accepted: accepted,
      rejected: rejected,
      quarantined: quarantined,
      stillPending: stillPending,
      httpStatus: lastHttp,
    );
  }

  int _backoffMs(int consecutiveFailures) {
    final base = min(
      30 * 1000 * pow(2, consecutiveFailures - 1).toInt(),
      30 * 60 * 1000,
    );
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    return (base * jitter).round();
  }

  void _incrementPendingAttempts(
    Map<String, LedgerEntry> entries,
    List<SyncRecord> records,
  ) {
    for (final r in records) {
      final e = entries[r.ledgerKey];
      if (e != null && e.state == LedgerState.pending) {
        entries[r.ledgerKey] = e.copyWith(attempts: e.attempts + 1);
      }
    }
  }

  String? _findKeyById(Map<String, LedgerEntry> entries, String id) {
    for (final k in entries.keys) {
      if (k.endsWith(':$id')) return k;
    }
    return null;
  }

  Set<String> _collectAcceptedIds(Map<String, dynamic> json) {
    final accepted = json['accepted'];
    final ids = <String>{};
    if (accepted is Map) {
      for (final list in accepted.values) {
        if (list is List) {
          for (final id in list) {
            if (id is String) ids.add(id);
          }
        }
      }
    }
    return ids;
  }

  List<SyncRecord> _sortPending(List<SyncRecord> records) {
    final workouts = records
        .where((r) => r.kind == SyncRecordKind.workout)
        .toList()
      ..sort((a, b) => (a.body['startTime'] as int).compareTo(b.body['startTime'] as int));
    final sleep = records
        .where((r) => r.kind == SyncRecordKind.sleep)
        .toList()
      ..sort(
          (a, b) => (a.body['beginUnix'] as int).compareTo(b.body['beginUnix'] as int));
    final totals = records
        .where((r) => r.kind == SyncRecordKind.dailyTotals)
        .toList()
      ..sort((a, b) => (a.body['dayKey'] as String).compareTo(b.body['dayKey'] as String));
    final hr = records
        .where((r) => r.kind == SyncRecordKind.heartRate)
        .toList()
      ..sort((a, b) => (a.body['dayKey'] as String).compareTo(b.body['dayKey'] as String));
    return [...workouts, ...sleep, ...totals, ...hr];
  }

  List<List<SyncRecord>> _buildChunks(List<SyncRecord> records, int nowMs) {
    final chunks = <List<SyncRecord>>[];
    var current = <SyncRecord>[];
    var currentBytes = 0;

    for (final r in records) {
      final bodyOnly = Map<String, dynamic>.from(r.body);
      final estBytes = utf8.encode(jsonEncode(bodyOnly)).length;
      if (current.isNotEmpty &&
          (current.length >= _maxRecordsPerChunk ||
              currentBytes + estBytes > _maxChunkBytes)) {
        chunks.add(current);
        current = [];
        currentBytes = 0;
      }
      current.add(r);
      currentBytes += estBytes;
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  Future<TransportResponse> _postChunk(
    List<SyncRecord> records, {
    required int chunkIndex,
    required int chunkCount,
    required int nowMs,
  }) async {
    final payload = <String, dynamic>{};
    for (final kind in SyncRecordKind.values) {
      final list =
          records.where((r) => r.kind == kind).map((r) => r.body).toList();
      if (list.isNotEmpty) {
        payload[kind.payloadKey] = list;
      }
    }
    final bodyWithoutMeta = Map<String, dynamic>.from(payload);
    final batchId = sha256
        .convert(utf8.encode(jsonEncode(bodyWithoutMeta)))
        .toString()
        .substring(0, 16);
    payload['meta'] = {
      'schemaVersion': 2,
      'batchId': batchId,
      'chunkIndex': chunkIndex,
      'chunkCount': chunkCount,
      'clientSentAtMs': nowMs,
    };
    final bodyBytes = utf8.encode(jsonEncode(payload));
    final bodySha = sha256.convert(bodyBytes).toString();
    return _transport.postSync(
      bodyBytes: bodyBytes,
      headers: {
        'Authorization': 'Bearer ${BackendConfig.writeKey}',
        'Content-Type': 'application/json',
        'X-Fathom-Body-Sha256': bodySha,
        'X-Fathom-Sync-Schema': '2',
      },
    );
  }

  Future<void> _reportQuarantine(SyncRecord r, String reason) async {
    final key = '${r.ledgerKey}:${r.contentHash}';
    if (_quarantineReported.contains(key)) return;
    _quarantineReported.add(key);
    await _telemetry.breadcrumb(
      'quarantine',
      data: {'kind': r.kind.name, 'reason': reason},
    );
  }

  void _emitStatus({bool? inFlight}) {
    _status.value = _status.value.copyWith(inFlight: inFlight);
  }

  void _emitStatusFromLedger(SyncLedgerData ledger) {
    var pending = 0;
    var quarantined = 0;
    for (final e in ledger.entries.values) {
      if (e.state == LedgerState.pending) pending++;
      if (e.state == LedgerState.quarantined) quarantined++;
    }
    _status.value = BackendSyncStatus(
      lastSuccessfulSync: ledger.lastSuccessfulSyncMs != null
          ? DateTime.fromMillisecondsSinceEpoch(ledger.lastSuccessfulSyncMs!)
          : null,
      pendingCount: pending,
      quarantinedCount: quarantined,
      inFlight: _inFlight,
      lastError: _status.value.lastError,
    );
  }

  @override
  void startRetryTimer() {
    _retryTimer?.cancel();
    _ledger.load().then((ledger) {
      final next = ledger.nextRetryAtMs;
      if (next == null) return;
      final delay = next - _now().millisecondsSinceEpoch;
      if (delay <= 0) {
        unawaited(push(SyncTrigger.retry));
        return;
      }
      _retryTimer = Timer(Duration(milliseconds: delay), () {
        unawaited(push(SyncTrigger.retry));
      });
    });
  }

  void _scheduleRetryTimer(int backoffMs) {
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: backoffMs), () {
      unawaited(push(SyncTrigger.retry));
    });
  }

  @override
  void stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> reconcileIfDue() async {
    final ledger = await _ledger.load();
    final nowMs = _now().millisecondsSinceEpoch;
    if (ledger.lastReconcileMs != null &&
        nowMs - ledger.lastReconcileMs! < const Duration(hours: 24).inMilliseconds) {
      return;
    }

    final from = _now().subtract(const Duration(days: 30));
    final fromDay =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final resp = await _transport.getManifest(fromDay: fromDay);
    if (resp.status == 404) {
      await _telemetry.breadcrumb('reconcile', data: {'reason': 'endpoint_missing'});
      final updated = ledger.copyWith(lastReconcileMs: nowMs);
      await _ledger.save(updated);
      return;
    }
    if (resp.status != 200 || resp.json == null) return;

    final records = await _snapshot.build() ?? [];
    final entries = Map<String, LedgerEntry>.from(ledger.entries);
    var pendingCount = 0;

    for (final r in records) {
      final entry = entries[r.ledgerKey];
      if (entry?.state != LedgerState.synced) continue;
      final serverHash = _manifestHash(resp.json!, r);
      final serverPresent = serverHash != _manifestMissing;
      if (!serverPresent ||
          (serverHash != null &&
              serverHash.isNotEmpty &&
              serverHash != r.contentHash)) {
        entries[r.ledgerKey] = LedgerEntry(
          state: LedgerState.pending,
          hash: r.contentHash,
          updatedAtMs: nowMs,
        );
        pendingCount++;
      }
    }

    var updated = ledger.copyWith(entries: entries, lastReconcileMs: nowMs);
    await _ledger.save(updated);
    await _telemetry.breadcrumb('reconcile', data: {'pendingCount': pendingCount});
    if (pendingCount > 0) {
      await push(SyncTrigger.reconcile);
    }
  }

  static const _manifestMissing = '__missing__';

  String? _manifestHash(Map<String, dynamic> manifest, SyncRecord r) {
    final list = manifest[r.kind.payloadKey] as List?;
    if (list == null) return _manifestMissing;
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['id'] as String?;
      if (id == r.id) {
        return item['contentHash'] as String?;
      }
    }
    return _manifestMissing;
  }

  /// Back-compat shim.
  Future<void> syncToBackend() => push(SyncTrigger.manual);

  // Migration helper for tests / one-time cleanup.
  Future<void> migrateLegacyPrefsKey() async {
    if (_prefs.containsKey(_legacyLastSyncKey)) {
      await _prefs.remove(_legacyLastSyncKey);
    }
  }
}

extension on BackendSyncStatus {
  BackendSyncStatus copyWith({
    DateTime? lastSuccessfulSync,
    int? pendingCount,
    int? quarantinedCount,
    bool? inFlight,
    String? lastError,
  }) {
    return BackendSyncStatus(
      lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
      pendingCount: pendingCount ?? this.pendingCount,
      quarantinedCount: quarantinedCount ?? this.quarantinedCount,
      inFlight: inFlight ?? this.inFlight,
      lastError: lastError ?? this.lastError,
    );
  }
}