import 'dart:convert';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';

/// GT5 WorkoutData `0x05` in-run sample records.
///
/// Wire record (8 bytes, ~5 s): `00 00 <marker> <cadence> <hr> 00 <u16>`.
/// The third-byte marker is sport-specific — not a universal magic:
/// - Walk (type 1): `0x22`, locked vs Walk #72 (HR 102–180, 229×5 s ≈ duration)
/// - Outdoor Run (type 2) / Indoor run (type 5): `0x23`, locked vs Outdoor #60
///
/// Sample u16 is not charted (time-misaligned vs HR on #60). Pace comes from
/// locked km splits. Unknown types decode nothing — never scan every marker.
abstract final class Gt5RunSampleParser {
  static const int walkMarker = 0x22;
  static const int runMarker = 0x23;
  static const int intervalSec = 5;

  /// Totals `0x14` type ids: Walk=1, Outdoor Run=2, Indoor run=5.
  static int? markerForWorkoutType(int workoutType) {
    switch (workoutType) {
      case 1:
        return walkMarker;
      case 2:
      case 5:
        return runMarker;
      default:
        return null;
    }
  }

  static List<RunStreamPoint> decode(
    List<PeeledPageBodies> pages, {
    required int workoutType,
  }) {
    final marker = markerForWorkoutType(workoutType);
    if (marker == null) return const [];
    return decodeGt5EightByteHrRecords(pages, marker: marker);
  }
}

/// Decodes GT5 sample streams for [workoutType]. See [Gt5RunSampleParser].
List<RunStreamPoint> decodeRunSamplePoints(
  List<PeeledPageBodies> pages, {
  required int workoutType,
}) =>
    Gt5RunSampleParser.decode(pages, workoutType: workoutType);

/// Walk leftover `0x05` bodies as 8-byte `00 00 <marker> …` HR/cadence records.
///
/// Shared by [Gt5RunSampleParser] and the type-gated in-session HR lock.
List<RunStreamPoint> decodeGt5EightByteHrRecords(
  List<PeeledPageBodies> pages, {
  required int marker,
}) {
  if (pages.isEmpty) return const [];

  final sorted = [...pages]..sort((a, b) => a.index.compareTo(b.index));
  final stream = <int>[];
  for (final page in sorted) {
    for (final body in page.bodies) {
      if (body.id != 0x05) continue;
      stream.addAll(_decodeBase64(body.bodyBase64));
    }
  }
  if (stream.length < 8) return const [];

  final points = <RunStreamPoint>[];
  var i = 0;
  var sampleIndex = 0;
  while (i + 8 <= stream.length) {
    if (stream[i] == 0x00 &&
        stream[i + 1] == 0x00 &&
        stream[i + 2] == marker) {
      final cadence = stream[i + 3];
      final hr = stream[i + 4];
      final cadOk = cadence >= 40 && cadence <= 250;
      points.add(
        RunStreamPoint(
          offsetSec: sampleIndex * Gt5RunSampleParser.intervalSec,
          hrBpm: (hr >= 40 && hr <= 220) ? hr : null,
          cadenceSpm: cadOk ? cadence : null,
        ),
      );
      sampleIndex++;
      i += 8;
    } else {
      i++;
    }
  }
  return points;
}

List<int> _decodeBase64(String b64) {
  if (b64.isEmpty) return const [];
  try {
    return base64Decode(b64);
  } catch (_) {
    return const [];
  }
}
