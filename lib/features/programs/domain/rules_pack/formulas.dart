/// Deterministic planning formulas for pool-swim Programs (Rules Pack v1).
///
/// Sources distilled in
/// `docs/brainstorms/research/2026-10-09-swim-training-algorithms-datasets.md` §6–7.
/// Numbers are planning heuristics, not physiology truth.
library;

// --- Capacity ladder -------------------------------------------------------

/// Default continuous-distance rung growth (+20%).
const double rungStepDefault = 0.20;

/// Minimum rung growth (near-pass half-step / fail recovery).
const double rungStepMin = 0.15;

/// Maximum rung growth (horizon compress ceiling).
const double rungStepMax = 0.25;

/// Fail-path next rung growth cap (≤10% volume / smaller capacity step).
const double rungStepAfterFail = 0.10;

/// Round continuous proof distances to this multiple (metres).
const int distanceRoundM = 50;

/// Sessions of exposure typically needed before a capacity proof.
const int sessionsPerRungDefault = 6;

/// Cap rung block length (weeks) — dogfood / R13 alignment.
const int rungBlockWeeksMax = 3;

/// Floor rung block length (weeks).
const int rungBlockWeeksMin = 2;

// --- Volume ----------------------------------------------------------------

/// Max week-over-week volume growth (fraction).
const double weeklyVolumeGrowthMax = 0.10;

/// Default week-over-week volume growth when building chores.
const double weeklyVolumeGrowthDefault = 0.08;

/// Deload factor every [deloadEveryWeeks] weeks.
const double deloadFactor = 0.80;

/// Insert a deload week every N weeks (after a peak).
const int deloadEveryWeeks = 4;

/// Key (endurance) session total distance clamp.
const int keySessionMinM = 1300;
const int keySessionMaxM = 2000;

/// Support session total distance clamp.
const int supportSessionMinM = 1000;
const int supportSessionMaxM = 1600;

// --- Warm-up / cool-down ---------------------------------------------------

const int warmUpFloorM = 300;
const int warmUpCeilM = 600;
const double warmUpFraction = 0.15;

const int coolDownFloorM = 100;
const int coolDownCeilM = 300;
const double coolDownFraction = 0.07;

// --- Pace / feasibility ----------------------------------------------------

/// Optimistic CSS gain (s/100 m per week) — Swim Smooth band.
const double cssGainOptimisticSecPer100PerWeek = 0.5;

/// Pessimistic CSS gain (s/100 m per week).
const double cssGainPessimisticSecPer100PerWeek = 0.3;

/// Plateau after this many weeks of CSS work (planning bound).
const int cssGainPlateauWeeks = 12;

/// Riegel exponent for distance time prediction (planning only).
const double riegelExponent = 1.06;

/// Taper days after final capacity/pace proof for goal-day forecast.
const int taperDaysMin = 3;
const int taperDaysMax = 5;

// --- Proof slip ------------------------------------------------------------

/// Near-pass: slip ~1 week, keep rung.
const int nearPassSlipDays = 7;

/// Fail: slip mid of 7–14 day band.
const int failSlipDays = 10;

/// Delay / pause family: slip one week by default.
const int delaySlipDays = 7;

/// Near-pass distance threshold vs rung target.
const double nearPassDistanceFraction = 0.90;

// --- Helpers ---------------------------------------------------------------

/// Round [metres] to nearest [distanceRoundM] (minimum one step when > 0).
int roundToPoolStep(int metres) {
  if (metres <= 0) return 0;
  const step = distanceRoundM;
  final rounded = ((metres + step ~/ 2) ~/ step) * step;
  return rounded < step ? step : rounded;
}

/// Clamp rung step into the pack band (default path uses [rungStepDefault]).
double clampRungStep(double step) {
  if (step < rungStepMin) return rungStepMin;
  if (step > rungStepMax) return rungStepMax;
  return step;
}

/// Next capacity rung after [currentM], stepping by [step] toward [goalM].
///
/// Returns [goalM] (rounded) when the stepped value would meet or pass the goal.
int nextCapacityRung({
  required int currentM,
  required int goalM,
  double step = rungStepDefault,
}) {
  if (currentM >= goalM) return roundToPoolStep(goalM);
  final s = clampRungStep(step);
  final raw = (currentM * (1.0 + s)).round();
  var next = roundToPoolStep(raw);
  if (next <= currentM) {
    next = currentM + distanceRoundM;
  }
  if (next >= goalM) {
    return roundToPoolStep(goalM);
  }
  return next;
}

/// Weeks in a rung block from sessions/week.
int rungBlockWeeks(int sessionsPerWeek) {
  final n = sessionsPerWeek < 1 ? 1 : sessionsPerWeek;
  final weeks = (sessionsPerRungDefault + n - 1) ~/ n; // ceil
  if (weeks < rungBlockWeeksMin) return rungBlockWeeksMin;
  if (weeks > rungBlockWeeksMax) return rungBlockWeeksMax;
  return weeks;
}

/// Warm-up distance for a session totaling [sessionTotalM].
int warmUpDistanceM(int sessionTotalM) {
  final raw = (sessionTotalM * warmUpFraction).round();
  if (raw < warmUpFloorM) return warmUpFloorM;
  if (raw > warmUpCeilM) return warmUpCeilM;
  return roundToPoolStep(raw);
}

/// Cool-down distance for a session totaling [sessionTotalM].
int coolDownDistanceM(int sessionTotalM) {
  final raw = (sessionTotalM * coolDownFraction).round();
  if (raw < coolDownFloorM) return coolDownFloorM;
  if (raw > coolDownCeilM) return coolDownCeilM;
  return roundToPoolStep(raw);
}

/// Main-set distance so WU + main + CD ≈ [sessionTotalM].
int mainDistanceM(int sessionTotalM) {
  final wu = warmUpDistanceM(sessionTotalM);
  final cd = coolDownDistanceM(sessionTotalM);
  final main = sessionTotalM - wu - cd;
  return main < distanceRoundM ? distanceRoundM : roundToPoolStep(main);
}

/// Clamp an integer into [[lo], [hi]].
int clampInt(int v, int lo, int hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}
