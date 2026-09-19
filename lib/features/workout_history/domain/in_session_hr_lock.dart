import 'dart:math' as math;

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/gt5_run_sample_parser.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';

/// Type-gated in-session HR lock over peeled WorkoutData leftover `0x05`.
///
/// Run packing (8-byte `00 00 <marker> <cadence> <hr> 00 <u16>`, ~5 s) is a
/// candidate decoder only when [markerForInSessionHrLock] returns a marker.
/// Outdoor/Indoor run (2/5) reuse Run's `0x23`. Walk (1) is `0x22`.
///
/// Swim pool (6), open water (8), and strength (140) owner peels #67/#56,
/// #27, and #70/#64 have leftover `0x05` bodies, but they are not this 8-byte
/// layout. Uncatalogued → empty. Do not scan unknown markers. Native
/// `hr_samples` is not a lock source.
List<RunStreamPoint> lockInSessionHrPoints(
  List<PeeledPageBodies> pages, {
  required int workoutType,
  int? hrMin,
  int? hrMax,
  int agreementToleranceBpm = 1,
}) {
  final marker = markerForInSessionHrLock(workoutType);
  if (marker == null || pages.isEmpty) return const [];

  final decoded = decodeGt5EightByteHrRecords(pages, marker: marker);
  final hrs = [
    for (final p in decoded)
      if (p.hrBpm != null) p.hrBpm!,
  ];
  if (hrs.length < 2) return const [];

  final seriesMin = hrs.reduce(math.min);
  final seriesMax = hrs.reduce(math.max);
  if (hrMin != null && (seriesMin - hrMin).abs() > agreementToleranceBpm) {
    return const [];
  }
  if (hrMax != null && (seriesMax - hrMax).abs() > agreementToleranceBpm) {
    return const [];
  }

  return [
    for (final p in decoded)
      RunStreamPoint(offsetSec: p.offsetSec, hrBpm: p.hrBpm),
  ];
}

/// Third-byte marker for the 8-byte sample walk, or null to omit.
///
/// Prefers [Gt5RunSampleParser.markerForWorkoutType] for Walk/Run/Indoor run —
/// this helper stays for the swim/strength omit gate.
int? markerForInSessionHrLock(int workoutType) {
  return Gt5RunSampleParser.markerForWorkoutType(workoutType);
}
