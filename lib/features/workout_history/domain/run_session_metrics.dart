import 'package:fitness_os/core/huawei/huawei_link.dart';

/// Decoded this-run tiles for Outdoor/Indoor Run detail (U4).
///
/// Only fields with a real DTO / store home are populated. Named new-oracle
/// tiles (VO₂, vertical oscillation, balance, session load, recovery, native
/// zone minutes) stay null until catalog promote + Totals decode — never
/// invent from leftovers or zeros.
class RunSessionMetrics {
  const RunSessionMetrics({
    this.recoverySec,
    this.aerobicEffect,
    this.anaerobicEffect,
    this.sessionLoad,
    this.hrZoneType,
    this.hrZoneMinutes,
    this.cadenceSpm,
    this.steps,
    this.strideCm,
    this.gctMs,
    this.elevGainM,
    this.vo2Max,
    this.verticalOscillationMm,
    this.balancePct,
  });

  /// Session-scoped recovery time (seconds). Not Recovery-tab rolling status.
  final int? recoverySec;
  final double? aerobicEffect;
  final double? anaerobicEffect;
  final int? sessionLoad;

  /// Native zone type label/id when fetched — never invented minutes.
  final String? hrZoneType;
  final List<int>? hrZoneMinutes;

  final int? cadenceSpm;
  final int? steps;
  final int? strideCm;
  final int? gctMs;
  final int? elevGainM;
  final double? vo2Max;
  final double? verticalOscillationMm;
  final double? balancePct;

  /// Map from lean [WorkoutSummary]. Today only [steps] has a DTO home among
  /// the 15-tile form list; the rest remain unobserved until Outdoor seed.
  factory RunSessionMetrics.fromSummary(WorkoutSummary w) {
    return RunSessionMetrics(steps: w.steps);
  }

  bool get hasThisRunTraining =>
      recoverySec != null ||
      aerobicEffect != null ||
      anaerobicEffect != null ||
      sessionLoad != null;

  /// Zones only when native type and/or native minutes arrived — never invent.
  bool get hasNativeZones =>
      (hrZoneType != null && hrZoneType!.isNotEmpty) ||
      (hrZoneMinutes != null && hrZoneMinutes!.isNotEmpty);

  bool get hasFormTiles =>
      cadenceSpm != null ||
      steps != null ||
      strideCm != null ||
      gctMs != null ||
      elevGainM != null ||
      vo2Max != null;

  /// Invent-guard: named VO / balance tiles require decoded fields.
  bool get hasVerticalOscillation => verticalOscillationMm != null;
  bool get hasBalance => balancePct != null;
  bool get hasVo2 => vo2Max != null;
  bool get hasNativeZoneMinutes =>
      hrZoneMinutes != null && hrZoneMinutes!.isNotEmpty;
}

/// One pace-block split row when distance and/or pace survived peel → meta.
class RunPaceSplit {
  const RunPaceSplit({
    required this.index,
    this.distanceM,
    this.paceSec,
  });

  final int index;
  final int? distanceM;
  final int? paceSec;

  bool get hasDistanceOrPace => distanceM != null || paceSec != null;
}

/// Decoded in-run sample point for pace / HR charts. Opaque side-file bytes
/// alone are not points — invent-guard returns an empty list until a real
/// decoder exists.
class RunStreamPoint {
  const RunStreamPoint({
    required this.offsetSec,
    this.paceSecPerKm,
    this.hrBpm,
  });

  final int offsetSec;
  final double? paceSecPerKm;
  final int? hrBpm;
}

/// Build split rows from persisted pace-block meta (distance/pace scalars).
///
/// Returns empty when no block has distance or pace — UI omits the section.
List<RunPaceSplit> runPaceSplitsFromPages(List<PeeledPageBodies> pages) {
  final out = <RunPaceSplit>[];
  for (final page in pages) {
    if (page.distanceM == null && page.paceSec == null) continue;
    out.add(
      RunPaceSplit(
        index: page.index,
        distanceM: page.distanceM,
        paceSec: page.paceSec,
      ),
    );
  }
  out.sort((a, b) => a.index.compareTo(b.index));
  return out;
}

/// Honest sample decode: opaque TLV bodies are not chart series.
///
/// When a real WorkoutData sample decoder lands, replace this stub. Until
/// then charts must stay omitted (AE2 / AE3) — never invent zeros.
List<RunStreamPoint> decodeRunSamplePoints(List<PeeledPageBodies> pages) {
  // Opaque leftover/sample bodies ≠ decoded pace/HR points.
  if (pages.isEmpty) return const [];
  return const [];
}

/// Invent-guard helpers for Run detail (AE3 / AE4).
abstract final class RunInventGuard {
  static bool showsVo2(RunSessionMetrics m) => m.hasVo2;
  static bool showsVerticalOscillation(RunSessionMetrics m) =>
      m.hasVerticalOscillation;
  static bool showsBalance(RunSessionMetrics m) => m.hasBalance;
  static bool showsNativeZoneMinutes(RunSessionMetrics m) =>
      m.hasNativeZoneMinutes;
  static bool showsThisRunTraining(RunSessionMetrics m) => m.hasThisRunTraining;
}
