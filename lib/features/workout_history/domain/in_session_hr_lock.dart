import 'dart:convert';
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
/// Strength (140) uses packed consecutive u8 BPM (~5 s).
/// Swim pool (6) / open water (8) use 7-byte `HR 00 A 00 B 00 C` records
/// (~5 s); first byte is BPM. Native `hr_samples` is not a lock source.
List<RunStreamPoint> lockInSessionHrPoints(
  List<PeeledPageBodies> pages, {
  required int workoutType,
  int? hrMin,
  int? hrMax,
  int agreementToleranceBpm = 1,
}) {
  if (pages.isEmpty) return const [];

  if (workoutType == strengthWorkoutType) {
    return _lockPackedBpmSeries(
      decodeStrengthPackedHrPoints(pages),
      hrMin: hrMin,
      hrMax: hrMax,
      agreementToleranceBpm: agreementToleranceBpm,
    );
  }

  if (workoutType == poolSwimWorkoutType ||
      workoutType == openWaterSwimWorkoutType) {
    return _lockPackedBpmSeries(
      decodeSwimSevenByteHrPoints(pages),
      hrMin: hrMin,
      hrMax: hrMax,
      agreementToleranceBpm: agreementToleranceBpm,
    );
  }

  final marker = markerForInSessionHrLock(workoutType);
  if (marker == null) return const [];

  final decoded = decodeGt5EightByteHrRecords(pages, marker: marker);
  return _lockPackedBpmSeries(
    decoded,
    hrMin: hrMin,
    hrMax: hrMax,
    agreementToleranceBpm: agreementToleranceBpm,
  );
}

/// Strength (140) WorkoutData `0x05`: consecutive u8 BPM at ~5 s.
///
/// Out-of-band bytes (including a leading `0x00` pad) become null HR slots so
/// offsets stay wall-clock aligned; the lock uses in-band values only.
List<RunStreamPoint> decodeStrengthPackedHrPoints(
  List<PeeledPageBodies> pages,
) {
  final stream = _concatOx05Bodies(pages);
  if (stream.isEmpty) return const [];

  const intervalSec = 5;
  final points = <RunStreamPoint>[];
  for (var i = 0; i < stream.length; i++) {
    final hr = stream[i];
    points.add(
      RunStreamPoint(
        offsetSec: i * intervalSec,
        hrBpm: (hr >= 40 && hr <= 220) ? hr : null,
      ),
    );
  }
  return points;
}

/// Swim (6/8) WorkoutData `0x05`: 7-byte `HR 00 A 00 B 00 C` at ~5 s.
///
/// Characterized on owner pool session #67: first byte matches Totals
/// hrMin/hrMax; positions 1/3/5 are zero pads. Truncated or misaligned
/// streams omit.
List<RunStreamPoint> decodeSwimSevenByteHrPoints(
  List<PeeledPageBodies> pages,
) {
  final stream = _concatOx05Bodies(pages);
  if (stream.length < 14 || stream.length % 7 != 0) return const [];

  const intervalSec = 5;
  const recordLen = 7;
  final points = <RunStreamPoint>[];
  for (var i = 0, sample = 0; i + recordLen <= stream.length; i += recordLen) {
    final rec = stream.sublist(i, i + recordLen);
    if (rec[1] != 0 || rec[3] != 0 || rec[5] != 0) {
      return const [];
    }
    final hr = rec[0];
    points.add(
      RunStreamPoint(
        offsetSec: sample * intervalSec,
        hrBpm: (hr >= 40 && hr <= 220) ? hr : null,
      ),
    );
    sample++;
  }
  return points;
}

List<RunStreamPoint> _lockPackedBpmSeries(
  List<RunStreamPoint> decoded, {
  int? hrMin,
  int? hrMax,
  int agreementToleranceBpm = 1,
}) {
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

/// Huawei strength workout type (free training / strength).
const strengthWorkoutType = 140;

/// Huawei pool swim.
const poolSwimWorkoutType = 6;

/// Huawei open-water swim.
const openWaterSwimWorkoutType = 8;

List<int> _concatOx05Bodies(List<PeeledPageBodies> pages) {
  if (pages.isEmpty) return const [];
  final sorted = [...pages]..sort((a, b) => a.index.compareTo(b.index));
  final stream = <int>[];
  for (final page in sorted) {
    for (final body in page.bodies) {
      if (body.id != 0x05) continue;
      stream.addAll(_decodeBase64(body.bodyBase64));
    }
  }
  return stream;
}

List<int> _decodeBase64(String b64) {
  if (b64.isEmpty) return const [];
  try {
    return base64Decode(b64);
  } catch (_) {
    return const [];
  }
}
