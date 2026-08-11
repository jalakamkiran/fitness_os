import 'package:fitness_os/core/huawei/huawei_link.dart';

/// TruSleep file `stateIntervals` → display sleep sessions (primary SoT).
///
/// Gap-merge ≤ [mergeGapSec] (3m). Does not invent stages — message-path
/// stages attach later by overlap.
abstract final class TruSleepSleepSot {
  static const mergeGapSec = 180;
  static const heroLookbackSec = 36 * 3600;

  /// Contiguous chains where consecutive intervals are within [gapSec].
  ///
  /// Input need not be sorted; result is chronological (begin ascending).
  static List<SleepStateInterval> gapMergeChains(
    List<SleepStateInterval> intervals, {
    int gapSec = mergeGapSec,
  }) {
    if (intervals.isEmpty) return const [];
    final sorted = List<SleepStateInterval>.from(intervals)
      ..sort((a, b) => a.beginUnix.compareTo(b.beginUnix));

    final chains = <SleepStateInterval>[];
    var begin = sorted.first.beginUnix;
    var end = sorted.first.endUnix;
    for (var i = 1; i < sorted.length; i++) {
      final next = sorted[i];
      if (next.beginUnix - end > gapSec) {
        chains.add(SleepStateInterval(beginUnix: begin, endUnix: end));
        begin = next.beginUnix;
        end = next.endUnix;
      } else {
        if (next.endUnix > end) end = next.endUnix;
        if (next.beginUnix < begin) begin = next.beginUnix;
      }
    }
    chains.add(SleepStateInterval(beginUnix: begin, endUnix: end));
    return chains;
  }

  /// One [SleepSessionSummary] per gap-merged chain (no stages, no wireType).
  static List<SleepSessionSummary> buildSessions(
    List<SleepStateInterval> intervals, {
    int gapSec = mergeGapSec,
  }) {
    return gapMergeChains(intervals, gapSec: gapSec)
        .map(
          (c) => SleepSessionSummary(
            beginUnix: c.beginUnix,
            endUnix: c.endUnix,
          ),
        )
        .toList();
  }

  /// Prefer longest session ending within the last 36h; else longest overall.
  static SleepSessionSummary? pickHeroSession(
    List<SleepSessionSummary> sessions, {
    required int nowUnix,
  }) {
    if (sessions.isEmpty) return null;
    final cutoff = nowUnix - heroLookbackSec;
    final recent = sessions.where((s) => s.endUnix >= cutoff).toList();
    final pool = recent.isNotEmpty ? recent : sessions;
    return pool.reduce((a, b) {
      final da = a.endUnix - a.beginUnix;
      final db = b.endUnix - b.beginUnix;
      return db > da ? b : a;
    });
  }
}
