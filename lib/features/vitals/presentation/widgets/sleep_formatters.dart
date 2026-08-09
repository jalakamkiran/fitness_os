import 'package:fitness_os/core/huawei/huawei_link.dart';

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
bool sleepCrossesLocalMidnight(SleepSessionSummary session) {
  final begin = sleepLocalFromUnix(session.beginUnix);
  final end = sleepLocalFromUnix(session.endUnix);
  return begin.year != end.year ||
      begin.month != end.month ||
      begin.day != end.day;
}

/// Most recent session whose local end falls on [now]'s calendar day.
SleepSessionSummary? todaysSleepSession(
  List<SleepSessionSummary> sessions, {
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  for (final s in sessions) {
    if (s.beginUnix <= 0 || s.endUnix <= s.beginUnix) continue;
    final end = sleepLocalFromUnix(s.endUnix);
    final endDay = DateTime(end.year, end.month, end.day);
    if (endDay == today) return s;
  }
  return null;
}

String sleepMonthLabel(int year, int month) {
  if (month < 1 || month > 12) return '$year';
  return '${_months[month - 1]} $year';
}
