import 'dart:convert';
import 'dart:typed_data';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';

/// Derived / display helpers for GT5 strength (type 140) session UI.
///
/// Never invents recovery % or HR curves. Null fields stay absent — do not
/// zero-fill missing watch scalars (0 is only shown when the watch sent 0).
class StrengthSessionMetrics {
  const StrengthSessionMetrics(this.workout);

  final WorkoutSummary workout;

  bool get isStrength => isStrengthWorkout(workout.type);

  /// Compact duration for hero chips (`53m`, `1h 12m`).
  String? get durationLabel {
    final sec = workout.durationSec;
    if (sec <= 0) return null;
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    if (m > 0) return '${m}m';
    return '${sec}s';
  }

  String? get caloriesLabel =>
      workout.calories == null ? null : '${workout.calories}';

  /// Heart-rate range from min–max when either bound is present.
  String? get hrRangeLabel {
    final min = workout.hrMin;
    final max = workout.hrMax;
    if (min != null && max != null) return '$min–$max';
    if (min != null) return '$min';
    if (max != null) return '$max';
    return null;
  }

  String? get loadLabel =>
      workout.load == null ? null : '${workout.load}';

  /// Watch [WorkoutSummary.recoveryTime] is minutes.
  String? get recoveryTimeLabel => formatRecoveryMinutes(workout.recoveryTime);

  String? get aerobicLabel =>
      workout.aerobicEffect == null ? null : '${workout.aerobicEffect}';

  String? get anaerobicLabel =>
      workout.anaerobicEffect == null ? null : '${workout.anaerobicEffect}';

  /// Calories per minute of session duration.
  String? get caloriesPerMinLabel {
    final cal = workout.calories;
    final sec = workout.durationSec;
    if (cal == null || sec <= 0) return null;
    final perMin = cal / (sec / 60.0);
    return perMin.toStringAsFixed(1);
  }

  /// Training load per hour of session duration.
  String? get loadPerHourLabel {
    final load = workout.load;
    final sec = workout.durationSec;
    if (load == null || sec <= 0) return null;
    final perHour = load / (sec / 3600.0);
    return perHour.toStringAsFixed(1);
  }

  bool get hasBasics =>
      durationLabel != null || caloriesLabel != null || hrRangeLabel != null;

  bool get hasImpact => loadLabel != null || recoveryTimeLabel != null;

  bool get hasIntensity =>
      caloriesPerMinLabel != null ||
      loadPerHourLabel != null ||
      aerobicLabel != null ||
      anaerobicLabel != null;
}

/// Formats watch recovery minutes for product UI (`1h`, `45m`, `1h 30m`).
String? formatRecoveryMinutes(int? minutes) {
  if (minutes == null) return null;
  if (minutes < 0) return null;
  if (minutes == 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}

/// Fill missing strength Totals scalars from leftover TLV bodies / blob.
///
/// Older Sync builds stored training-load (`0x0d`) and recovery (`0x11`) as
/// leftovers instead of summary fields. Strength UI only reads summary
/// scalars — promote without inventing when the tag body is absent.
WorkoutSummary promoteStrengthScalarsFromLeftovers(
  WorkoutSummary workout, {
  List<LeftoverTlvBody> leftoverBodies = const [],
  Uint8List? leftoverBytes,
}) {
  if (!isStrengthWorkout(workout.type)) return workout;
  final needsLoad = workout.load == null;
  final needsRecovery = workout.recoveryTime == null;
  final needsAerobic = workout.aerobicEffect == null;
  final needsAnaerobic = workout.anaerobicEffect == null;
  final needsPoints = workout.trainingPoints == null;
  if (!needsLoad &&
      !needsRecovery &&
      !needsAerobic &&
      !needsAnaerobic &&
      !needsPoints) {
    return workout;
  }

  final bodies = <LeftoverTlvBody>[
    ...leftoverBodies,
    if (leftoverBytes != null && leftoverBytes.isNotEmpty)
      ...leftoverBodiesFromEncodedTlvs(leftoverBytes),
  ];
  if (bodies.isEmpty) return workout;

  int? load = workout.load;
  int? recovery = workout.recoveryTime;
  int? aerobic = workout.aerobicEffect;
  int? anaerobic = workout.anaerobicEffect;
  int? trainingPoints = workout.trainingPoints;

  for (final body in bodies) {
    final raw = _decodeBodyBase64(body.bodyBase64);
    final be = _readBeInt(raw);
    if (be == null) continue;
    switch (body.id) {
      case 0x0d:
        load ??= be;
      case 0x0e:
        aerobic ??= be;
      case 0x11:
        recovery ??= be;
      case 0x20:
        anaerobic ??= be;
      case 0x63:
        trainingPoints ??= be;
    }
  }

  if (load == workout.load &&
      recovery == workout.recoveryTime &&
      aerobic == workout.aerobicEffect &&
      anaerobic == workout.anaerobicEffect &&
      trainingPoints == workout.trainingPoints) {
    return workout;
  }

  return workout.copyWith(
    load: load,
    recoveryTime: recovery,
    aerobicEffect: aerobic,
    anaerobicEffect: anaerobic,
    trainingPoints: trainingPoints,
  );
}

/// Decode a Huawei TLV blob (same framing as Totals leftoverBytes) into
/// channel-style leftover bodies.
List<LeftoverTlvBody> leftoverBodiesFromEncodedTlvs(List<int> buf) {
  final out = <LeftoverTlvBody>[];
  var i = 0;
  while (i < buf.length) {
    final tag = buf[i++] & 0xff;
    if (i >= buf.length) break;
    var length = 0;
    var guards = 0;
    while (i < buf.length) {
      final b = buf[i++] & 0xff;
      length = (length << 7) | (b & 0x7f);
      guards++;
      if ((b & 0x80) == 0) break;
      if (guards > 5) return out;
    }
    if (i + length > buf.length) break;
    final value = buf.sublist(i, i + length);
    i += length;
    out.add(
      LeftoverTlvBody(
        id: tag,
        len: value.length,
        bodyBase64: base64Encode(value),
      ),
    );
  }
  return out;
}

List<int> _decodeBodyBase64(String b64) {
  if (b64.isEmpty) return const [];
  try {
    return base64Decode(b64);
  } catch (_) {
    return const [];
  }
}

int? _readBeInt(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > 4) return null;
  var v = 0;
  for (final b in bytes) {
    v = (v << 8) | (b & 0xff);
  }
  return v;
}

/// Chronological strength sessions ending at [current], newest last, max [limit].
List<WorkoutSummary> recentStrengthLoads({
  required WorkoutSummary current,
  required List<WorkoutSummary> all,
  int limit = 8,
}) {
  final strength = all.where((w) => isStrengthWorkout(w.type)).toList()
    ..sort((a, b) {
      final byStart = a.startTime.compareTo(b.startTime);
      if (byStart != 0) return byStart;
      return a.number.compareTo(b.number);
    });

  final idx = strength.indexWhere(
    (w) => w.number == current.number && w.startTime == current.startTime,
  );
  if (idx < 0) {
    // Current not in history yet — show current alone rather than a wrong window.
    return [current];
  }
  final endExclusive = idx + 1;
  final start = (endExclusive - limit).clamp(0, endExclusive);
  return strength.sublist(start, endExclusive);
}
