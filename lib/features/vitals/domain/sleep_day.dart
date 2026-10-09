import 'package:fitness_os/core/huawei/huawei_link.dart';

/// Huawei-aligned sleep-day + nocturnal bout helpers.
///
/// Sleep-day `D` covers local `[D-1 20:00, D 20:00)`. Mid-night wake gaps up to
/// [nocturnalMergeGapSec] are treated as WASO inside one overnight bout, not
/// as separate naps.
abstract final class SleepDay {
  static const napMaxSec = 3 * 3600;
  static const microMergeGapSec = 180;
  static const nocturnalMergeGapSec = 90 * 60;

  /// Calendar date id for the current Huawei sleep-day relative to [now].
  ///
  /// After local 20:00, the current sleep-day flips to tomorrow's date.
  static DateTime sleepDayId(DateTime now) => sleepDayIdForOnset(now);

  /// Sleep-day id that owns a session by **onset** (begin local).
  static DateTime sleepDayIdForOnset(DateTime beginLocal) {
    if (beginLocal.hour >= 20) {
      final next = beginLocal.add(const Duration(days: 1));
      return DateTime(next.year, next.month, next.day);
    }
    return DateTime(beginLocal.year, beginLocal.month, beginLocal.day);
  }

  static DateTime sleepDayIdForSession(SleepSessionSummary session) {
    final begin = _localFromUnix(session.beginUnix);
    return sleepDayIdForOnset(begin);
  }

  /// Half-open window `[D-1 20:00, D 20:00)`.
  static (DateTime start, DateTime end) windowFor(DateTime sleepDay) {
    final d = DateTime(sleepDay.year, sleepDay.month, sleepDay.day);
    final end = DateTime(d.year, d.month, d.day, 20);
    final start = end.subtract(const Duration(days: 1));
    return (start, end);
  }

  static bool isMember(SleepSessionSummary session, DateTime sleepDay) {
    if (session.beginUnix <= 0 || session.endUnix <= session.beginUnix) {
      return false;
    }
    return sleepDayIdForSession(session) ==
        DateTime(sleepDay.year, sleepDay.month, sleepDay.day);
  }

  /// Coalesce mid-night fragments into overnight bouts (presentation + SoT).
  static List<SleepSessionSummary> coalesceNocturnalSessions(
    List<SleepSessionSummary> sessions, {
    int microGapSec = microMergeGapSec,
    int nocturnalGapSec = nocturnalMergeGapSec,
  }) {
    final valid = sessions
        .where((s) => s.beginUnix > 0 && s.endUnix > s.beginUnix)
        .toList()
      ..sort((a, b) => a.beginUnix.compareTo(b.beginUnix));
    if (valid.isEmpty) return <SleepSessionSummary>[];

    final out = <SleepSessionSummary>[];
    var cur = valid.first;
    for (var i = 1; i < valid.length; i++) {
      final next = valid[i];
      final gap = next.beginUnix - cur.endUnix;
      if (_shouldMergeNocturnal(cur, next, gap,
          microGapSec: microGapSec, nocturnalGapSec: nocturnalGapSec)) {
        cur = _mergeSessions(cur, next);
      } else {
        out.add(cur);
        cur = next;
      }
    }
    out.add(cur);
    return out;
  }

  /// Resolve current sleep-day aggregate for Today / Home primary picker.
  ///
  /// [scientificMainKeys] marks SEQUENCE scientific mains (mergeKey) so short
  /// scientific nights still rank as overnight primary (R4).
  static SleepDayAggregate resolve(
    List<SleepSessionSummary> sessions, {
    DateTime? now,
    Set<String> scientificMainKeys = const {},
  }) {
    final n = now ?? DateTime.now();
    final dayId = sleepDayId(n);
    final coalesced = coalesceNocturnalSessions(sessions);
    final members = coalesced.where((s) => isMember(s, dayId)).toList()
      ..sort((a, b) => a.beginUnix.compareTo(b.beginUnix));

    if (members.isEmpty) {
      return SleepDayAggregate(
        sleepDay: dayId,
        members: const [],
        totalDurationSec: 0,
        primary: null,
        napSessions: const [],
      );
    }

    final total = members.fold<int>(0, (sum, s) => sum + s.durationSec);
    final primary = _rankPrimary(members, scientificMainKeys: scientificMainKeys);
    final naps = primary == null
        ? const <SleepSessionSummary>[]
        : members
            .where(
              (s) =>
                  s.mergeKey != primary.mergeKey &&
                  isIntentionalNap(
                    s,
                    scientificMain: scientificMainKeys.contains(s.mergeKey),
                  ),
            )
            .toList();

    return SleepDayAggregate(
      sleepDay: dayId,
      members: members,
      totalDurationSec: total,
      primary: primary,
      napSessions: naps,
    );
  }

  /// Intentional daytime / short sleep — not a mid-night overnight fragment.
  ///
  /// When [scientificMain] is true (SEQUENCE scientific night), never a nap.
  static bool isIntentionalNap(
    SleepSessionSummary session, {
    bool scientificMain = false,
  }) {
    if (scientificMain) return false;
    if (session.beginUnix <= 0 || session.endUnix <= session.beginUnix) {
      return false;
    }
    if (session.durationSec >= napMaxSec) return false;
    if (_crossesMidnight(session)) return false;
    final begin = _localFromUnix(session.beginUnix);
    // Evening onset on the sleep-day is overnight territory even if short.
    if (begin.hour >= 20 || begin.hour < 5) return false;
    return true;
  }

  /// Main nocturnal (or ≥3h / scientific-main) sleep — opposite of intentional nap.
  static bool isMainNightSleep(
    SleepSessionSummary session, {
    bool scientificMain = false,
  }) {
    if (session.beginUnix <= 0 || session.endUnix <= session.beginUnix) {
      return false;
    }
    return !isIntentionalNap(session, scientificMain: scientificMain);
  }

  static String kindLabel(
    SleepSessionSummary session, {
    bool scientificMain = false,
  }) {
    if (isIntentionalNap(session, scientificMain: scientificMain)) {
      return 'nap';
    }
    return 'overnight';
  }

  static bool _shouldMergeNocturnal(
    SleepSessionSummary a,
    SleepSessionSummary b,
    int gap, {
    required int microGapSec,
    required int nocturnalGapSec,
  }) {
    if (gap <= microGapSec) return true;
    if (gap > nocturnalGapSec) return false;
    if (sleepDayIdForSession(a) != sleepDayIdForSession(b)) return false;

    // Beyond micro-merge: never glue an intentional nap (afternoon, or
    // post-wakeup orphan after a SEQUENCE main) onto the prior bout.
    if (isIntentionalNap(b)) return false;
    return true;
  }

  static SleepSessionSummary _mergeSessions(
    SleepSessionSummary a,
    SleepSessionSummary b,
  ) {
    final stages = a.stages.length >= b.stages.length ? a.stages : b.stages;
    return SleepSessionSummary(
      beginUnix: a.beginUnix <= b.beginUnix ? a.beginUnix : b.beginUnix,
      endUnix: a.endUnix >= b.endUnix ? a.endUnix : b.endUnix,
      wireType: a.wireType ?? b.wireType,
      stages: stages,
    );
  }

  static SleepSessionSummary? _rankPrimary(
    List<SleepSessionSummary> members, {
    Set<String> scientificMainKeys = const {},
  }) {
    if (members.isEmpty) return null;
    SleepSessionSummary? best;
    var bestRank = -1;
    var bestDur = -1;
    for (final s in members) {
      final rank = _primaryRank(
        s,
        scientificMain: scientificMainKeys.contains(s.mergeKey),
      );
      if (rank > bestRank ||
          (rank == bestRank && s.durationSec > bestDur)) {
        best = s;
        bestRank = rank;
        bestDur = s.durationSec;
      }
    }
    return best;
  }

  /// Higher is better: scientific main, then ≥3h midnight-crossing, ≥3h,
  /// midnight-crossing / nocturnal onset, longest fallback.
  static int _primaryRank(
    SleepSessionSummary s, {
    bool scientificMain = false,
  }) {
    if (scientificMain) return 5;
    final long = s.durationSec >= napMaxSec;
    final overnight = _crossesMidnight(s) || _nocturnalOnset(s);
    if (long && overnight) return 4;
    if (long) return 3;
    if (overnight) return 2;
    return 1;
  }

  static bool _nocturnalOnset(SleepSessionSummary session) {
    final begin = _localFromUnix(session.beginUnix);
    return begin.hour >= 20 || begin.hour < 5;
  }

  static bool _crossesMidnight(SleepSessionSummary session) {
    final begin = _localFromUnix(session.beginUnix);
    final end = _localFromUnix(session.endUnix);
    return begin.year != end.year ||
        begin.month != end.month ||
        begin.day != end.day;
  }

  static DateTime _localFromUnix(int unixSec) =>
      DateTime.fromMillisecondsSinceEpoch(unixSec * 1000, isUtc: true)
          .toLocal();
}

/// Presentation aggregate for one Huawei sleep-day.
class SleepDayAggregate {
  const SleepDayAggregate({
    required this.sleepDay,
    required this.members,
    required this.totalDurationSec,
    required this.primary,
    required this.napSessions,
  });

  final DateTime sleepDay;
  final List<SleepSessionSummary> members;
  final int totalDurationSec;
  final SleepSessionSummary? primary;
  final List<SleepSessionSummary> napSessions;

  bool get isEmpty => primary == null || members.isEmpty;

  int get napCount => napSessions.length;

  int get napDurationSec =>
      napSessions.fold<int>(0, (sum, s) => sum + s.durationSec);
}
