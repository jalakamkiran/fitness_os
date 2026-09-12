import 'package:fitness_os/core/huawei/huawei_link.dart';

/// Frozen from owner 25m pool probe (2026-07-23): type=6 is pool (GB=6 / OW=8).
const Map<int, String> kWorkoutTypeLabels = <int, String>{
  1: 'Walk',
  2: 'Run',
  3: 'Cycle',
  4: 'Climb',
  5: 'Indoor run',
  6: 'Pool swim',
  7: 'Indoor cycle',
  8: 'Open water',
  9: 'Elliptical',
  10: 'Rower',
  140: 'Strength',
};

String workoutTypeLabel(int type) =>
    kWorkoutTypeLabels[type] ?? 'Workout type $type';

bool isSwimWorkout(int type) => type == 6 || type == 8;

/// Land cardio for the Run/Walk tab: Walk (1), Outdoor Run (2), Indoor run (5).
/// Mixed outdoor sessions sometimes wire as Walk when a walk segment dominates.
bool isRunWorkout(int type) => type == 1 || type == 2 || type == 5;

/// Outdoor Run (Totals/list type 2). Walk (1) / Indoor run (5) are never the Outdoor prove.
bool isOutdoorRunWorkout(int type) => type == 2;

bool isStrengthWorkout(int type) => type == 140;

String formatWorkoutWhen(int unixSec) {
  if (unixSec <= 0) return 'unknown time';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000).toLocal();
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
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
  String two(int n) => n.toString().padLeft(2, '0');
  return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} · '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// Clock-style duration for list rows (`42:18` / `1:05:02`).
String formatDurationClock(int sec) {
  if (sec <= 0) return '—';
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '${two(m)}:${two(s)}';
}

String formatDistanceM(int? meters) {
  if (meters == null || meters <= 0) return '—';
  final raw = meters.toString();
  final buf = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final fromEnd = raw.length - i;
    buf.write(raw[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
  }
  return '${buf.toString()} m';
}

/// Product distance (`2.79 km`) — omit when unknown.
String? formatDistanceKm(int? meters) {
  if (meters == null || meters <= 0) return null;
  final km = meters / 1000.0;
  if (km >= 10) return '${km.toStringAsFixed(1)} km';
  return '${km.toStringAsFixed(2)} km';
}

/// Average pace from distance + duration (`7'46"`).
String? formatAvgPaceSecPerKm(int? distanceM, int durationSec) {
  if (distanceM == null || distanceM <= 0 || durationSec <= 0) return null;
  final secPerKm = (durationSec / (distanceM / 1000.0)).round();
  return formatPaceSecPerKm(secPerKm);
}

/// Pace as `6'22"` /km style; null/non-positive → null.
String? formatPaceSecPerKm(int? paceSec) {
  if (paceSec == null || paceSec <= 0) return null;
  final m = paceSec ~/ 60;
  final s = paceSec % 60;
  return "$m'${s.toString().padLeft(2, '0')}\"";
}

/// Compact duration for run/strength heroes (`21:40`, `53m`).
String? formatDurationHero(int sec) {
  if (sec <= 0) return null;
  if (sec < 3600) return formatDurationClock(sec);
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (m > 0) return '${h}h ${m}m';
  return '${h}h';
}

/// Outdoor land (Walk / Outdoor Run) — not Indoor run (5).
bool isOutdoorLandWorkout(int type) => type == 1 || type == 2;

String workoutSessionTitle(WorkoutSummary w) {
  final label = workoutTypeLabel(w.type);
  return '$label · #${w.number}';
}

/// Alias kept for swim-list call sites.
String swimSessionTitle(WorkoutSummary w) => workoutSessionTitle(w);
