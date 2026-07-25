/// P0 swim metrics — pure functions over session + lap evidence.
///
/// No AGPL. Units: pace = seconds per 100 m; stroke rate = strokes per minute.
library;

enum SwimHrCoverage {
  /// In-workout sample stream present (`sampleCount` > 0).
  present,

  /// Totals HR peaks only — no sample stream.
  partial,

  /// No HR fields.
  absent,
}

class SwimLapMetrics {
  const SwimLapMetrics({
    required this.index,
    this.distanceM,
    this.durationSec,
    this.strokes,
    this.swolf,
    this.paceSecPer100m,
    this.style,
  });

  final int index;
  final int? distanceM;
  final int? durationSec;
  final int? strokes;
  final int? swolf;
  final int? paceSecPer100m;
  final int? style;

  Map<String, dynamic> toJson() => {
        'index': index,
        if (distanceM != null) 'distanceM': distanceM,
        if (durationSec != null) 'durationSec': durationSec,
        if (strokes != null) 'strokes': strokes,
        if (swolf != null) 'swolf': swolf,
        if (paceSecPer100m != null) 'paceSecPer100m': paceSecPer100m,
        if (style != null) 'style': style,
      };

  factory SwimLapMetrics.fromJson(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    return SwimLapMetrics(
      index: asInt(map['index']) ?? 0,
      distanceM: asInt(map['distanceM']),
      durationSec: asInt(map['durationSec']),
      strokes: asInt(map['strokes']),
      swolf: asInt(map['swolf'] ?? map['avgSwolf']),
      paceSecPer100m: asInt(map['paceSecPer100m']),
      style: asInt(map['style']),
    );
  }
}

class SwimP0Metrics {
  const SwimP0Metrics({
    required this.hrCoverage,
    this.avgPaceSecPer100m,
    this.movingAvgPaceSecPer100m,
    this.totalStrokes,
    this.avgSwolf,
    this.strokeRatePerMin,
    this.lapCount,
    this.reportedLaps,
    this.lengthCoveragePartial = false,
    this.laps = const [],
  });

  final SwimHrCoverage hrCoverage;
  final int? avgPaceSecPer100m;
  final int? movingAvgPaceSecPer100m;
  final int? totalStrokes;
  final int? avgSwolf;
  final int? strokeRatePerMin;
  final int? lapCount;
  final int? reportedLaps;

  /// True when watch `laps` &gt; parsed segment rows (honest PARTIAL).
  final bool lengthCoveragePartial;
  final List<SwimLapMetrics> laps;

  Map<String, dynamic> toJson() => {
        'hrCoverage': hrCoverage.name,
        if (avgPaceSecPer100m != null) 'avgPaceSecPer100m': avgPaceSecPer100m,
        if (movingAvgPaceSecPer100m != null)
          'movingAvgPaceSecPer100m': movingAvgPaceSecPer100m,
        if (totalStrokes != null) 'totalStrokes': totalStrokes,
        if (avgSwolf != null) 'avgSwolf': avgSwolf,
        if (strokeRatePerMin != null) 'strokeRatePerMin': strokeRatePerMin,
        if (lapCount != null) 'lapCount': lapCount,
        if (reportedLaps != null) 'reportedLaps': reportedLaps,
        'lengthCoveragePartial': lengthCoveragePartial,
        'laps': laps.map((l) => l.toJson()).toList(),
      };

  factory SwimP0Metrics.fromJson(Map<String, dynamic> map) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    final hrName = map['hrCoverage'] as String? ?? 'absent';
    final hr = SwimHrCoverage.values.firstWhere(
      (e) => e.name == hrName,
      orElse: () => SwimHrCoverage.absent,
    );
    final rawLaps = map['laps'];
    final laps = rawLaps is List
        ? rawLaps
            .whereType<Map>()
            .map((e) => SwimLapMetrics.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <SwimLapMetrics>[];
    return SwimP0Metrics(
      hrCoverage: hr,
      avgPaceSecPer100m: asInt(map['avgPaceSecPer100m']),
      movingAvgPaceSecPer100m: asInt(map['movingAvgPaceSecPer100m']),
      totalStrokes: asInt(map['totalStrokes']),
      avgSwolf: asInt(map['avgSwolf']),
      strokeRatePerMin: asInt(map['strokeRatePerMin']),
      lapCount: asInt(map['lapCount']),
      reportedLaps: asInt(map['reportedLaps']),
      lengthCoveragePartial: map['lengthCoveragePartial'] == true,
      laps: laps,
    );
  }
}

/// Build P0 metrics from Totals + parsed segments.
///
/// [poolLengthCm] is wire tag units (cm). [poolLengthM] overrides when known.
SwimP0Metrics computeSwimP0({
  required int durationSec,
  int? distanceM,
  int? strokes,
  int? avgSwolf,
  int? strokeRate,
  int? laps,
  int? sampleCount,
  int? hrMin,
  int? hrMax,
  int? hrPeak,
  int? poolLengthCm,
  List<SwimLapMetrics> segmentLaps = const [],
}) {
  final ordered = [...segmentLaps]..sort((a, b) => a.index.compareTo(b.index));
  final withPace = ordered.map((lap) {
    final pace = lap.paceSecPer100m ??
        _paceSecPer100m(lap.durationSec, lap.distanceM);
    return SwimLapMetrics(
      index: lap.index,
      distanceM: lap.distanceM,
      durationSec: lap.durationSec,
      strokes: lap.strokes,
      swolf: lap.swolf,
      paceSecPer100m: pace,
      style: lap.style,
    );
  }).toList();

  final movingDist = _sumPositive(withPace.map((l) => l.distanceM));
  final movingDur = _sumPositive(withPace.map((l) => l.durationSec));
  final movingPace = _paceSecPer100m(movingDur, movingDist);

  final sessionPace = _paceSecPer100m(durationSec, distanceM);

  final lapStrokes = _sumPositive(withPace.map((l) => l.strokes));
  final totalStrokes = strokes ?? (lapStrokes > 0 ? lapStrokes : null);

  final derivedRate = _strokeRatePerMin(totalStrokes, movingDur > 0 ? movingDur : durationSec);
  final rate = strokeRate ?? derivedRate;

  final lengthPartial =
      laps != null && withPace.isNotEmpty && withPace.length < laps;

  return SwimP0Metrics(
    hrCoverage: _hrCoverage(
      sampleCount: sampleCount,
      hrMin: hrMin,
      hrMax: hrMax,
      hrPeak: hrPeak,
    ),
    avgPaceSecPer100m: sessionPace,
    movingAvgPaceSecPer100m: movingPace,
    totalStrokes: totalStrokes,
    avgSwolf: avgSwolf,
    strokeRatePerMin: rate,
    lapCount: withPace.isEmpty ? null : withPace.length,
    reportedLaps: laps,
    lengthCoveragePartial: lengthPartial,
    laps: withPace,
  );
}

SwimHrCoverage _hrCoverage({
  int? sampleCount,
  int? hrMin,
  int? hrMax,
  int? hrPeak,
}) {
  if (sampleCount != null && sampleCount > 0) return SwimHrCoverage.present;
  if (hrMin != null || hrMax != null || hrPeak != null) {
    return SwimHrCoverage.partial;
  }
  return SwimHrCoverage.absent;
}

int? _paceSecPer100m(int? durationSec, int? distanceM) {
  if (durationSec == null || distanceM == null) return null;
  if (durationSec <= 0 || distanceM <= 0) return null;
  return (durationSec * 100) ~/ distanceM;
}

int? _strokeRatePerMin(int? strokes, int durationSec) {
  if (strokes == null || strokes <= 0 || durationSec <= 0) return null;
  return (strokes * 60) ~/ durationSec;
}

int _sumPositive(Iterable<int?> values) {
  var sum = 0;
  for (final v in values) {
    if (v != null && v > 0) sum += v;
  }
  return sum;
}

/// Wire pool length is centimetres on GT5 Totals `0x18`.
int? poolLengthCmToMeters(int? poolLengthCm) {
  if (poolLengthCm == null || poolLengthCm <= 0) return null;
  if (poolLengthCm >= 100) return poolLengthCm ~/ 100;
  return poolLengthCm; // already metres on some firmwares
}
