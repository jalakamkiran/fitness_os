/// Per-session recovery hours: watch SoT when present, else derived estimate.
///
/// Huawei Workout status docs note Recovery / Training load may be unavailable
/// for swimming (and some other modes) — estimates are expected Fathom fill,
/// not a missing Totals decode. v0 uses named constants only (no owner
/// auto-fit calibration).
///
/// Never mutates [WorkoutSummary.recoveryTime].
library;

import 'package:fitness_os/core/huawei/huawei_link.dart';

/// Provenance for a resolved session recovery value.
enum SessionRecoverySource {
  /// Watch Totals `recoveryTime` minutes.
  watch,

  /// Fathom estimate when watch recovery was absent.
  estimated,
}

/// Resolved session recovery without writing back to the summary.
class SessionRecoveryResolved {
  const SessionRecoveryResolved({
    required this.hours,
    required this.source,
  });

  /// Recovery contribution in hours.
  final double hours;

  final SessionRecoverySource source;
}

/// TE → hours bands (wire TE = aerobic/anaerobic ÷ 10).
const List<(double maxTeExclusive, double hours)> kTeRecoveryHoursTable = [
  (1.5, 6),
  (2.5, 12),
  (3.5, 24),
  (4.5, 36),
];

const double kTeRecoveryHoursAbove = 48;
const double kEstimateHoursMin = 4;
const double kEstimateHoursMax = 72;

/// Duration×intensity multipliers (hours = durationHours × mult).
const double kIntensityEasy = 4;
const double kIntensityModerate = 8;
const double kIntensityHard = 12;
const double kIntensityVeryHard = 18;

/// Prefer watch minutes; else TE → load → HR → duration×sport default.
///
/// Returns null when recovery is absent and duration is unusable (≤ 0).
SessionRecoveryResolved? resolveSessionRecovery(WorkoutSummary workout) {
  final watchMin = workout.recoveryTime;
  if (watchMin != null) {
    return SessionRecoveryResolved(
      hours: watchMin / 60.0,
      source: SessionRecoverySource.watch,
    );
  }

  if (workout.durationSec <= 0) return null;

  final teHours = _hoursFromTrainingEffect(workout);
  if (teHours != null) {
    return SessionRecoveryResolved(
      hours: _clampEstimate(teHours),
      source: SessionRecoverySource.estimated,
    );
  }

  final loadHours = _hoursFromLoad(workout.load);
  if (loadHours != null) {
    return SessionRecoveryResolved(
      hours: _clampEstimate(loadHours),
      source: SessionRecoverySource.estimated,
    );
  }

  final hrHours = _hoursFromHr(workout);
  if (hrHours != null) {
    return SessionRecoveryResolved(
      hours: _clampEstimate(hrHours),
      source: SessionRecoverySource.estimated,
    );
  }

  final durationH = workout.durationSec / 3600.0;
  final mult = _sportIntensityMult(workout.type);
  return SessionRecoveryResolved(
    hours: _clampEstimate(durationH * mult),
    source: SessionRecoverySource.estimated,
  );
}

double? _hoursFromTrainingEffect(WorkoutSummary w) {
  final a = w.aerobicEffect;
  final n = w.anaerobicEffect;
  if (a == null && n == null) return null;
  final wire = [
    if (a != null) a,
    if (n != null) n,
  ].reduce((x, y) => x > y ? x : y);
  final te = wire / 10.0;
  for (final (maxTe, hours) in kTeRecoveryHoursTable) {
    if (te < maxTe) return hours;
  }
  return kTeRecoveryHoursAbove;
}

/// Simple load → hours map (watch load scale is unitless).
double? _hoursFromLoad(int? load) {
  if (load == null || load < 0) return null;
  return 4 + load / 8.0;
}

double? _hoursFromHr(WorkoutSummary w) {
  final peak = w.hrPeak ?? w.hrMax;
  if (peak == null || peak <= 0) return null;
  final durationH = w.durationSec / 3600.0;
  // Light tiering from peak HR without claiming zone science.
  final double mult;
  if (peak >= 170) {
    mult = kIntensityVeryHard;
  } else if (peak >= 150) {
    mult = kIntensityHard;
  } else if (peak >= 130) {
    mult = kIntensityModerate;
  } else {
    mult = kIntensityEasy;
  }
  return durationH * mult;
}

double _sportIntensityMult(int type) {
  // Pool / open water — Huawei often omits recovery; default moderate.
  if (type == 6 || type == 8) return kIntensityModerate;
  // Strength
  if (type == 140) return kIntensityHard;
  // Common run / walk / cycle-ish free training — moderate-hard default.
  if (type == 1 || type == 2 || type == 3 || type == 4 || type == 5) {
    return kIntensityHard;
  }
  return kIntensityModerate;
}

double _clampEstimate(double hours) {
  if (hours < kEstimateHoursMin) return kEstimateHoursMin;
  if (hours > kEstimateHoursMax) return kEstimateHoursMax;
  return hours;
}
