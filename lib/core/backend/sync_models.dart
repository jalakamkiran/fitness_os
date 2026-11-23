enum SyncTrigger {
  open,
  postWatch,
  manual,
  background,
  retry,
  reconcile,
}

extension SyncTriggerBreadcrumb on SyncTrigger {
  String get breadcrumbStage => switch (this) {
        SyncTrigger.open => 'open_push',
        SyncTrigger.postWatch => 'post_watch_push',
        SyncTrigger.manual => 'manual_push',
        SyncTrigger.background => 'background_push',
        SyncTrigger.retry => 'retry',
        SyncTrigger.reconcile => 'reconcile',
      };

  /// Strongest trigger wins for follow-up coalescing.
  int get priority => switch (this) {
        SyncTrigger.manual => 5,
        SyncTrigger.postWatch => 4,
        SyncTrigger.open => 3,
        SyncTrigger.background => 2,
        SyncTrigger.retry => 1,
        SyncTrigger.reconcile => 0,
      };
}

enum SyncRecordKind {
  workout,
  sleep,
  dailyTotals,
  heartRate,
}

extension SyncRecordKindWire on SyncRecordKind {
  String get payloadKey => switch (this) {
        SyncRecordKind.workout => 'workouts',
        SyncRecordKind.sleep => 'sleep',
        SyncRecordKind.dailyTotals => 'dailyTotals',
        SyncRecordKind.heartRate => 'heartRate',
      };
}

class SyncRecord {
  SyncRecord({
    required this.kind,
    required this.id,
    required this.body,
    required this.contentHash,
  });

  final SyncRecordKind kind;
  final String id;
  final Map<String, dynamic> body;
  final String contentHash;

  String get ledgerKey => '${kind.name}:$id';
}

enum LedgerState { synced, pending, quarantined }

class LedgerEntry {
  const LedgerEntry({
    required this.state,
    required this.hash,
    required this.updatedAtMs,
    this.ackedAtMs,
    this.attempts = 0,
    this.reason,
  });

  final LedgerState state;
  final String hash;
  final int updatedAtMs;
  final int? ackedAtMs;
  final int attempts;
  final String? reason;

  LedgerEntry copyWith({
    LedgerState? state,
    String? hash,
    int? updatedAtMs,
    int? ackedAtMs,
    int? attempts,
    String? reason,
    bool clearAckedAtMs = false,
    bool clearReason = false,
  }) {
    return LedgerEntry(
      state: state ?? this.state,
      hash: hash ?? this.hash,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      ackedAtMs: clearAckedAtMs ? null : (ackedAtMs ?? this.ackedAtMs),
      attempts: attempts ?? this.attempts,
      reason: clearReason ? null : (reason ?? this.reason),
    );
  }

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'hash': hash,
        'updatedAtMs': updatedAtMs,
        if (ackedAtMs != null) 'ackedAtMs': ackedAtMs,
        'attempts': attempts,
        if (reason != null) 'reason': reason,
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      state: LedgerState.values.byName(json['state'] as String),
      hash: json['hash'] as String,
      updatedAtMs: json['updatedAtMs'] as int,
      ackedAtMs: json['ackedAtMs'] as int?,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String?,
    );
  }
}

class SyncLedgerData {
  static const schemaVersion = 1;

  const SyncLedgerData({
    this.lastSuccessfulSyncMs,
    this.lastAckMs,
    this.nextRetryAtMs,
    this.consecutiveFailures = 0,
    this.lastReconcileMs,
    this.fullResyncRequired = false,
    this.entries = const {},
  });

  final int? lastSuccessfulSyncMs;
  final int? lastAckMs;
  final int? nextRetryAtMs;
  final int consecutiveFailures;
  final int? lastReconcileMs;
  final bool fullResyncRequired;
  final Map<String, LedgerEntry> entries;

  SyncLedgerData copyWith({
    int? lastSuccessfulSyncMs,
    int? lastAckMs,
    int? nextRetryAtMs,
    int? consecutiveFailures,
    int? lastReconcileMs,
    bool? fullResyncRequired,
    Map<String, LedgerEntry>? entries,
    bool clearNextRetryAtMs = false,
    bool clearLastSuccessfulSyncMs = false,
  }) {
    return SyncLedgerData(
      lastSuccessfulSyncMs: clearLastSuccessfulSyncMs
          ? null
          : (lastSuccessfulSyncMs ?? this.lastSuccessfulSyncMs),
      lastAckMs: lastAckMs ?? this.lastAckMs,
      nextRetryAtMs:
          clearNextRetryAtMs ? null : (nextRetryAtMs ?? this.nextRetryAtMs),
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastReconcileMs: lastReconcileMs ?? this.lastReconcileMs,
      fullResyncRequired: fullResyncRequired ?? this.fullResyncRequired,
      entries: entries ?? this.entries,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'lastSuccessfulSyncMs': lastSuccessfulSyncMs,
        'lastAckMs': lastAckMs,
        'nextRetryAtMs': nextRetryAtMs,
        'consecutiveFailures': consecutiveFailures,
        'lastReconcileMs': lastReconcileMs,
        'fullResyncRequired': fullResyncRequired,
        'entries': entries.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory SyncLedgerData.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as Map<String, dynamic>? ?? {};
    final entries = <String, LedgerEntry>{};
    for (final e in rawEntries.entries) {
      entries[e.key] =
          LedgerEntry.fromJson(Map<String, dynamic>.from(e.value as Map));
    }
    return SyncLedgerData(
      lastSuccessfulSyncMs: json['lastSuccessfulSyncMs'] as int?,
      lastAckMs: json['lastAckMs'] as int?,
      nextRetryAtMs: json['nextRetryAtMs'] as int?,
      consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,
      lastReconcileMs: json['lastReconcileMs'] as int?,
      fullResyncRequired: json['fullResyncRequired'] as bool? ?? false,
      entries: entries,
    );
  }
}

class PushOutcome {
  const PushOutcome({
    required this.trigger,
    required this.ok,
    this.attempted = 0,
    this.accepted = 0,
    this.rejected = 0,
    this.quarantined = 0,
    this.stillPending = 0,
    this.skippedDisabled = false,
    this.queued = false,
    this.httpStatus,
  });

  final SyncTrigger trigger;
  final bool ok;
  final int attempted;
  final int accepted;
  final int rejected;
  final int quarantined;
  final int stillPending;
  final bool skippedDisabled;
  final bool queued;
  final int? httpStatus;
}

class QuarantinedLedgerItem {
  const QuarantinedLedgerItem({
    required this.kind,
    required this.id,
    required this.reason,
  });

  final SyncRecordKind kind;
  final String id;
  final String reason;
}

class BackendSyncStatus {
  const BackendSyncStatus({
    this.lastSuccessfulSync,
    this.pendingCount = 0,
    this.quarantinedCount = 0,
    this.quarantinedItems = const [],
    this.inFlight = false,
    this.lastError,
  });

  final DateTime? lastSuccessfulSync;
  final int pendingCount;
  final int quarantinedCount;
  final List<QuarantinedLedgerItem> quarantinedItems;
  final bool inFlight;
  final String? lastError;
}