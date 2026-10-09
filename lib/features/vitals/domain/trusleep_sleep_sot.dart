import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/sleep_day.dart';

/// TruSleep file `stateIntervals` → display sleep sessions (primary SoT).
///
/// Micro gap-merge ≤ [mergeGapSec] (3m) for adjacent file fragments, then
/// nocturnal coalesce (≤90m mid-night wakes) via [SleepDay.coalesceNocturnalSessions].
/// Does not invent stages — message-path stages attach later by overlap.
abstract final class TruSleepSleepSot {
  /// Micro fragment glue (file-adjacent). Prefer [SleepDay.microMergeGapSec].
  static const mergeGapSec = SleepDay.microMergeGapSec;
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

  /// One [SleepSessionSummary] per nocturnal bout (micro-merge + overnight coalesce).
  static List<SleepSessionSummary> buildSessions(
    List<SleepStateInterval> intervals, {
    int gapSec = mergeGapSec,
  }) {
    final micro = gapMergeChains(intervals, gapSec: gapSec)
        .map(
          (c) => SleepSessionSummary(
            beginUnix: c.beginUnix,
            endUnix: c.endUnix,
          ),
        )
        .toList();
    return SleepDay.coalesceNocturnalSessions(micro);
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
