import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';

/// Canonical swim session persisted as a side-file after Sync.
///
/// Built from [WorkoutSummary] Totals + segments. Sample payloads stay out of
/// this cut — [SwimP0Metrics.hrCoverage] records honesty instead.
class CanonicalSwimSession {
  const CanonicalSwimSession({
    required this.workoutNumber,
    required this.startTime,
    required this.endTime,
    required this.durationSec,
    required this.type,
    required this.p0,
    this.distanceM,
    this.poolLengthM,
    this.swimType,
    this.builtAtUnix,
  });

  final int workoutNumber;
  final int startTime;
  final int endTime;
  final int durationSec;
  final int type;
  final int? distanceM;
  final int? poolLengthM;
  final int? swimType;
  final SwimP0Metrics p0;
  final int? builtAtUnix;

  Map<String, dynamic> toJson() => {
        'workoutNumber': workoutNumber,
        'startTime': startTime,
        'endTime': endTime,
        'durationSec': durationSec,
        'type': type,
        if (distanceM != null) 'distanceM': distanceM,
        if (poolLengthM != null) 'poolLengthM': poolLengthM,
        if (swimType != null) 'swimType': swimType,
        if (builtAtUnix != null) 'builtAtUnix': builtAtUnix,
        'p0': p0.toJson(),
      };

  factory CanonicalSwimSession.fromJson(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    final p0Raw = map['p0'];
    final p0 = p0Raw is Map
        ? SwimP0Metrics.fromJson(Map<String, dynamic>.from(p0Raw))
        : const SwimP0Metrics(hrCoverage: SwimHrCoverage.absent);
    return CanonicalSwimSession(
      workoutNumber: asInt(map['workoutNumber']) ?? 0,
      startTime: asInt(map['startTime']) ?? 0,
      endTime: asInt(map['endTime']) ?? 0,
      durationSec: asInt(map['durationSec']) ?? 0,
      type: asInt(map['type']) ?? 0,
      distanceM: asInt(map['distanceM']),
      poolLengthM: asInt(map['poolLengthM']),
      swimType: asInt(map['swimType']),
      builtAtUnix: asInt(map['builtAtUnix']),
      p0: p0,
    );
  }

  /// Pool + open-water types observed on GT5-A07 (6 / 8) plus swim field presence.
  /// Indoor run (5) and indoor cycle (7) are not swims.
  static bool looksLikeSwim(WorkoutSummary w) {
    if (w.type == 6 || w.type == 8) return true;
    if (w.type == 5 || w.type == 7) return false;
    return w.poolLength != null ||
        w.strokes != null ||
        w.avgSwolf != null ||
        (w.segments != null && w.segments!.isNotEmpty);
  }

  static CanonicalSwimSession? fromWorkoutSummary(
    WorkoutSummary w, {
    int? builtAtUnix,
  }) {
    if (!looksLikeSwim(w)) return null;

    final segmentLaps = (w.segments ?? const <WorkoutSegment>[])
        .map(
          (s) => SwimLapMetrics(
            index: s.index,
            distanceM: s.distanceM,
            durationSec: s.durationSec,
            strokes: s.strokes,
            swolf: s.avgSwolf,
            paceSecPer100m: s.paceSecPer100m,
            style: s.style ?? s.swimType,
          ),
        )
        .toList();

    final p0 = computeSwimP0(
      durationSec: w.durationSec,
      distanceM: w.distanceM,
      strokes: w.strokes,
      avgSwolf: w.avgSwolf,
      strokeRate: w.strokeRate,
      laps: w.laps,
      sampleCount: w.sampleCount,
      hrMin: w.hrMin,
      hrMax: w.hrMax,
      hrPeak: w.hrPeak,
      poolLengthCm: w.poolLength,
      segmentLaps: segmentLaps,
    );

    return CanonicalSwimSession(
      workoutNumber: w.number,
      startTime: w.startTime,
      endTime: w.endTime,
      durationSec: w.durationSec,
      type: w.type,
      distanceM: w.distanceM,
      poolLengthM: poolLengthCmToMeters(w.poolLength),
      swimType: w.swimType,
      p0: p0,
      builtAtUnix: builtAtUnix,
    );
  }
}
