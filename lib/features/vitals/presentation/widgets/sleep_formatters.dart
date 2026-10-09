import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/sleep_day.dart';

/// Wire timestamps are UTC unix seconds; display uses device local.
DateTime sleepLocalFromUnix(int unixSec) {
  return DateTime.fromMillisecondsSinceEpoch(unixSec * 1000, isUtc: true)
      .toLocal();
}

String sleepFormatDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

String sleepFormatHm(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _weekdays = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

String sleepFormatDayLabel(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}';

/// e.g. `Sun 9 Aug`
String sleepFormatShortDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// e.g. `23:18 → 06:30`
String sleepFormatWindow(int beginUnix, int endUnix) {
  final begin = sleepLocalFromUnix(beginUnix);
  final end = sleepLocalFromUnix(endUnix);
  return '${sleepFormatHm(begin)} → ${sleepFormatHm(end)}';
}

/// Full range used on older vitals rows.
String sleepFormatRange(int beginUnix, int endUnix) {
  final begin = sleepLocalFromUnix(beginUnix);
  final end = sleepLocalFromUnix(endUnix);
  final start = sleepFormatHm(begin);
  final stop = sleepFormatHm(end);
  final sameDay = begin.year == end.year &&
      begin.month == end.month &&
      begin.day == end.day;
  if (sameDay) return '${sleepFormatDayLabel(begin)} · $start – $stop';
  return '${sleepFormatDayLabel(begin)} $start – ${sleepFormatDayLabel(end)} $stop';
}

/// True when local begin/end fall on different calendar days (midnight crossing).
///
/// Prefer [sleepIsMainOvernight] / [sleepSessionKindLabel] for product kind.
bool sleepCrossesLocalMidnight(SleepSessionSummary session) {
  final begin = sleepLocalFromUnix(session.beginUnix);
  final end = sleepLocalFromUnix(session.endUnix);
  return begin.year != end.year ||
      begin.month != end.month ||
      begin.day != end.day;
}

/// True for intentional daytime / short naps (not overnight fragments).
bool sleepIsIntentionalNap(
  SleepSessionSummary session, {
  bool scientificMain = false,
}) =>
    SleepDay.isIntentionalNap(session, scientificMain: scientificMain);

/// True for main overnight / scientific-main sessions.
bool sleepIsMainOvernight(
  SleepSessionSummary session, {
  bool scientificMain = false,
}) =>
    SleepDay.isMainNightSleep(session, scientificMain: scientificMain);

/// Display kind: `nap` or `overnight`.
String sleepSessionKindLabel(
  SleepSessionSummary session, {
  bool scientificMain = false,
}) =>
    SleepDay.kindLabel(session, scientificMain: scientificMain);

/// Today's primary sleep for Home / Sleep hero.
///
/// Prefers the current Huawei sleep-day aggregate primary. Falls back to
/// longest coalesced session ending on the local calendar day.
SleepSessionSummary? todaysSleepSession(
  List<SleepSessionSummary> sessions, {
  DateTime? now,
}) {
  final aggregate = SleepDay.resolve(sessions, now: now);
  if (aggregate.primary != null) return aggregate.primary;

  // Legacy fallback when sleep-day empty (e.g. tests / edge clocks).
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final coalesced = SleepDay.coalesceNocturnalSessions(sessions);
  final endingToday = <SleepSessionSummary>[];
  for (final s in coalesced) {
    if (s.beginUnix <= 0 || s.endUnix <= s.beginUnix) continue;
    final end = sleepLocalFromUnix(s.endUnix);
    final endDay = DateTime(end.year, end.month, end.day);
    if (endDay == today) endingToday.add(s);
  }
  if (endingToday.isEmpty) return null;
  final overnight =
      endingToday.where((s) => sleepIsMainOvernight(s)).toList();
  if (overnight.isNotEmpty) {
    overnight.sort((a, b) => b.durationSec.compareTo(a.durationSec));
    return overnight.first;
  }
  endingToday.sort((a, b) => b.durationSec.compareTo(a.durationSec));
  return endingToday.first;
}

String sleepMonthLabel(int year, int month) {
  if (month < 1 || month > 12) return '$year';
  return '${_months[month - 1]} $year';
}
