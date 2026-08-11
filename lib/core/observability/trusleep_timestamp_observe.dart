import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/trusleep_sleep_sot.dart';

/// Temporary TruSleep vs message-path timestamp observe (Sentry).
///
/// Privacy: scalars + one compact tails string only — no PPG / sleep_data /
/// stage lists / MAC. Remove after ~5–6 owner Syncs settle the Health delta.
abstract final class TruSleepTimestampObserve {
  static const fingerprint = ['trusleep', 'timestamp-observe'];
  static const category = 'trusleep.observe';
  static const mergeGapSec = TruSleepSleepSot.mergeGapSec;

  /// Build allowlisted compare fields from one Sync result.
  static Map<String, Object?> buildPayload({
    required List<SleepSessionSummary> messageSessions,
    required List<SleepEnrichOutcome> enrich,
    WatchClockSnapshot? watchClock,
    int? nowUnix,
  }) {
    final intervals = <SleepStateInterval>[];
    var stateLen = 0;
    var dataLen = 0;
    for (final o in enrich) {
      if (!o.present) continue;
      if (intervals.isEmpty && o.stateIntervals.isNotEmpty) {
        intervals.addAll(o.stateIntervals);
      }
      for (final r in o.refs) {
        final id = r.id.toLowerCase();
        if (id.contains('state')) stateLen = r.len;
        if (id.contains('data')) dataLen = r.len;
      }
    }

    final sorted = List<SleepStateInterval>.from(intervals)
      ..sort((a, b) => a.beginUnix.compareTo(b.beginUnix));
    final latest = sorted.isEmpty ? null : sorted.last;
    final merged = mergeNearAdjacent(sorted, gapSec: mergeGapSec);

    final now = nowUnix ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final msg = pickRecentOvernight(messageSessions, nowUnix: now);

    final fileBegin = merged?.beginUnix ?? latest?.beginUnix;
    final fileEnd = merged?.endUnix ?? latest?.endUnix;
    int? deltaStart;
    int? deltaEnd;
    if (fileBegin != null && msg != null) {
      deltaStart = ((fileBegin - msg.beginUnix) / 60).round();
    }
    if (fileEnd != null && msg != null) {
      deltaEnd = ((fileEnd - msg.endUnix) / 60).round();
    }

    return {
      if (watchClock != null) ...{
        'zone_id': watchClock.zoneId,
        'offset_sec': watchClock.offsetSec,
        'offset_label': watchClock.offsetLabel,
        if (watchClock.skewSec != null) 'skew_sec': watchClock.skewSec,
        if (watchClock.phoneUnix != null) 'phone_unix': watchClock.phoneUnix,
        if (watchClock.deviceUnix != null) 'device_unix': watchClock.deviceUnix,
      },
      'file_interval_count': sorted.length,
      if (latest != null) ...{
        'file_latest_begin': latest.beginUnix,
        'file_latest_end': latest.endUnix,
        'file_latest_dur_min':
            ((latest.endUnix - latest.beginUnix) / 60).round(),
      },
      if (merged != null) ...{
        'file_merged_begin': merged.beginUnix,
        'file_merged_end': merged.endUnix,
        'file_merged_dur_min':
            ((merged.endUnix - merged.beginUnix) / 60).round(),
      },
      'msg_session_count': messageSessions.length,
      if (msg != null) ...{
        'msg_begin': msg.beginUnix,
        'msg_end': msg.endUnix,
        'msg_dur_min': ((msg.endUnix - msg.beginUnix) / 60).round(),
      },
      if (deltaStart != null) 'delta_start_min': deltaStart,
      if (deltaEnd != null) 'delta_end_min': deltaEnd,
      if (stateLen > 0) 'state_len': stateLen,
      if (dataLen > 0) 'data_len': dataLen,
      'tails': formatTails(sorted, max: 5),
    };
  }

  /// Merge trailing near-adjacent intervals (gap ≤ [gapSec]) into one window.
  ///
  /// Shared rule with [TruSleepSleepSot.gapMergeChains] — returns the last
  /// chain (most recent contiguous overnight/nap fragment group).
  static SleepStateInterval? mergeNearAdjacent(
    List<SleepStateInterval> sortedAsc, {
    int gapSec = mergeGapSec,
  }) {
    final chains = TruSleepSleepSot.gapMergeChains(sortedAsc, gapSec: gapSec);
    return chains.isEmpty ? null : chains.last;
  }

  /// Prefer longest session ending within the last 36h; else longest overall.
  static SleepSessionSummary? pickRecentOvernight(
    List<SleepSessionSummary> sessions, {
    required int nowUnix,
  }) =>
      TruSleepSleepSot.pickHeroSession(sessions, nowUnix: nowUnix);

  /// Compact `begin-end|…` for last [max] intervals (unix seconds).
  static String formatTails(List<SleepStateInterval> sortedAsc, {int max = 5}) {
    if (sortedAsc.isEmpty) return '';
    final start = sortedAsc.length > max ? sortedAsc.length - max : 0;
    return sortedAsc
        .sublist(start)
        .map((i) => '${i.beginUnix}-${i.endUnix}')
        .join('|');
  }

  static Future<void> report({
    required List<SleepSessionSummary> messageSessions,
    required List<SleepEnrichOutcome> enrich,
    WatchClockSnapshot? watchClock,
  }) async {
    if (!Sentry.isEnabled) return;
    // Nothing useful yet (no file intervals and no message sessions).
    final hasFile = enrich.any((e) => e.present && e.stateIntervals.isNotEmpty);
    if (!hasFile && messageSessions.isEmpty) return;

    final data = buildPayload(
      messageSessions: messageSessions,
      enrich: enrich,
      watchClock: watchClock,
    );
    final delta = data['delta_start_min'];
    final msg =
        'trusleep.observe Δstart=${delta ?? 'n/a'}m '
        'file=${data['file_merged_dur_min'] ?? data['file_latest_dur_min'] ?? 0}m '
        'msg=${data['msg_dur_min'] ?? 0}m';

    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: category,
        message: msg,
        level: SentryLevel.info,
        data: Map<String, dynamic>.from(data),
      ),
    );

    // One grouped Issue for easy multi-session compare; delete after ~5–6 Syncs.
    await Sentry.captureMessage(
      msg,
      level: SentryLevel.info,
      withScope: (scope) {
        scope.fingerprint = fingerprint;
        scope.setTag('feature', 'trusleep_observe');
        scope.setContexts('trusleep_observe', data);
      },
    );
  }
}
