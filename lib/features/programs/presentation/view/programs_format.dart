import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';

/// Tiny distance formatter for Programs UI (avoids locale/ReDoS pitfalls).
String formatMeters(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  if (n < 0) buf.write('-');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Format seconds as `m:ss` / `mm:ss`.
String formatMmSs(int totalSec) {
  final s = totalSec < 0 ? 0 : totalSec;
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

/// Pace per 100 m from total distance and duration.
String? formatPacePer100(int distanceM, int durationSec) {
  if (distanceM < 50 || durationSec <= 0) return null;
  final per100 = (durationSec / (distanceM / 100)).round();
  return '${formatMmSs(per100)} /100 m';
}

/// Hero goal line: `1,200 m` or `1,200 m in 24:00`.
String formatGoalLine(ProgramIntake intake) {
  final dist = '${formatMeters(intake.goalDistanceM)} m';
  final t = intake.targetTimeSec;
  if (t == null || t <= 0) return dist;
  return '$dist in ${formatMmSs(t)}';
}

/// Week / frequency chips for Agon home.
String formatWeekChip(Program program, DateTime now) {
  final weeks = program.intake.horizonWeeks;
  if (program.activatedAtMs == null) return 'Week · $weeks wk horizon';
  final start = DateTime.fromMillisecondsSinceEpoch(program.activatedAtMs!);
  final elapsed = now.difference(start).inDays;
  final week = (elapsed ~/ 7).clamp(0, weeks - 1) + 1;
  return 'Week $week of $weeks';
}

String formatSessionsChip(ProgramIntake intake) =>
    '${intake.sessionsPerWeek}×/week';

/// Trial label for a milestone (index is 0-based).
String formatTrialName(Milestone m) => 'Trial ${m.index + 1}';

String formatTrialSpec(Milestone m, {int? goalTimeSec}) {
  final dist = '${formatMeters(m.targetDistanceM)} m non-stop';
  if (goalTimeSec != null && goalTimeSec > 0) {
    return '$dist · ≤ ${formatMmSs(goalTimeSec)}';
  }
  final pace = m.targetPaceSecPer100;
  if (pace != null && pace > 0) {
    return '$dist · ${formatMmSs(pace.round())} /100 m';
  }
  return dist;
}

/// Home course structure — never implies the total is continuous.
String formatCourseStructureLine(ChoreSession chore) {
  final total = formatMeters(chore.targetDistanceM);
  if (!chore.hasWuMainCd) return '$total m';
  return 'WU · Main with rests · CD · $total m';
}

/// Short title for course / session hero from focus line.
String formatCourseTitle(ChoreSession chore) {
  final focus = chore.focusLine?.trim();
  if (focus != null && focus.isNotEmpty) return focus;
  switch (chore.role) {
    case ChoreRole.endurance:
      return 'Endurance swim';
    case ChoreRole.quality:
      return 'Quality set';
    case ChoreRole.technique:
      return 'Technique';
    case ChoreRole.recovery:
      return 'Recovery';
    case ChoreRole.proof:
      return 'Trial swim';
    case ChoreRole.guidedTest:
      return 'Guided test';
    case ChoreRole.easy:
      return 'Easy swim';
  }
}

/// Main-set summary under the course title (broken volume, not continuous).
String formatMainSetSummary(ChoreSession chore) {
  final main = chore.blocks.where((b) => b.part == 'main').toList();
  if (main.isEmpty) return 'Course with rests · not continuous';
  if (main.length == 1) {
    final b = main.first;
    final rest = b.restGuidanceSec;
    if (rest != null && rest > 0) {
      return '${b.label} · rest ${rest}s · not continuous';
    }
    // Continuous-looking main still sits inside WU/CD — clarify.
    if (chore.hasWuMainCd) {
      return 'Main with rests · not continuous';
    }
    return '${b.label} · ${formatMeters(b.distanceM)} m';
  }
  final totalMain = main.fold<int>(0, (s, b) => s + b.distanceM);
  return '${main.length} main sets · ${formatMeters(totalMain)} m · with rests';
}

DateTime? tryParseIsoDay(String dayIso) {
  final parts = dayIso.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final mo = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || mo == null || d == null) return null;
  return DateTime(y, mo, d);
}

/// Short calendar label, e.g. `Sat Oct 31`.
String formatShortDate(String dayIso) {
  final dt = tryParseIsoDay(dayIso);
  if (dt == null) return dayIso;
  const dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mon = [
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
  return '${dow[dt.weekday - 1]} ${mon[dt.month - 1]} ${dt.day}';
}

/// Day label for layer tag, e.g. `Fri Oct 9 · Training`.
String formatCourseDayTag(String dayIso, {String role = 'Training'}) {
  final short = formatShortDate(dayIso);
  if (short == dayIso) return role;
  return '$short · $role';
}

int sumPartMeters(List<ChoreBlock> blocks, String part) => blocks
    .where((b) => b.part == part)
    .fold<int>(0, (s, b) => s + b.distanceM);

/// Friendly rest label for set rows.
String formatRestGuidance(int? restSec) {
  if (restSec == null) return 'rest —';
  if (restSec <= 0) return 'rest —';
  if (restSec < 60) return 'rest :$restSec';
  return 'rest ${formatMmSs(restSec)}';
}

/// Streak floor hint: ceil(spw / 2) of spw.
String formatStreakFloorHint(int sessionsPerWeek) {
  final n = sessionsPerWeek.clamp(2, 5);
  final floor = (n + 1) ~/ 2;
  return 'Streak holds at $floor of $n';
}
