import 'package:fitness_os/core/huawei/huawei_link.dart';

/// Builds a Training Center XML (TCX) document from a [WorkoutSummary].
///
/// Fathom does not persist GPS. Strava still requires a **distance stream**:
/// lap-level [DistanceMeters] alone is ignored and shows as 0 km. We synthesize
/// a [Track] of [Trackpoint]s with cumulative distance (no Position).
String buildWorkoutTcx(WorkoutSummary workout) {
  final sport = _tcxSport(workout.type);
  final id = _isoUtc(DateTime.fromMillisecondsSinceEpoch(
    workout.startTime * 1000,
    isUtc: true,
  ));
  final notes = _notes(workout);
  final laps = _lapsXml(workout);

  return '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
  <Activities>
    <Activity Sport="$sport">
      <Id>$id</Id>
$laps      <Notes>${_escapeXml(notes)}</Notes>
      <Creator xsi:type="Device_t">
        <Name>Fathom</Name>
        <UnitId>0</UnitId>
        <ProductID>0</ProductID>
      </Creator>
    </Activity>
  </Activities>
  <Author xsi:type="Application_t">
    <Name>Fathom</Name>
    <Build>
      <Version>
        <VersionMajor>0</VersionMajor>
        <VersionMinor>1</VersionMinor>
      </Version>
    </Build>
    <LangID>en</LangID>
    <PartNumber>000-00000-00</PartNumber>
  </Author>
</TrainingCenterDatabase>
''';
}

/// Filename stem for cache / share (no directory, no extension).
String workoutTcxFileStem(WorkoutSummary workout) {
  final start = DateTime.fromMillisecondsSinceEpoch(
    workout.startTime * 1000,
    isUtc: true,
  );
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${start.year}${two(start.month)}${two(start.day)}_${two(start.hour)}${two(start.minute)}${two(start.second)}';
  return 'fathom_${_slugSport(workout.type)}_$stamp';
}

String _tcxSport(int type) {
  // TCX Sport_t is Running|Biking|Other. Map walk/swim/strength to Other;
  // Strava infers Walk/Swim from filename notes or athlete edit after upload.
  // Using non-schema values like "Walking" can make Strava drop metrics.
  switch (type) {
    case 2:
    case 5:
      return 'Running';
    case 3:
    case 7:
      return 'Biking';
    default:
      return 'Other';
  }
}

String _slugSport(int type) {
  switch (type) {
    case 1:
      return 'walk';
    case 2:
      return 'run';
    case 3:
      return 'cycle';
    case 5:
      return 'indoor_run';
    case 6:
      return 'pool_swim';
    case 7:
      return 'indoor_cycle';
    case 8:
      return 'open_water';
    case 9:
      return 'elliptical';
    case 10:
      return 'rower';
    case 140:
      return 'strength';
    default:
      return 'workout_$type';
  }
}

String _notes(WorkoutSummary workout) {
  final parts = <String>[
    'Exported from Fathom (Huawei GT5 companion).',
    'No GPS track — distance is synthetic from session totals for Strava.',
    'Huawei type=${workout.type} (${_humanSport(workout.type)}) #${workout.number}.',
  ];
  if (workout.poolLength != null) {
    parts.add('Pool length ${_formatPoolLengthCm(workout.poolLength!)}.');
  }
  if (workout.strokes != null) {
    parts.add('Strokes ${workout.strokes}.');
  }
  if (workout.avgSwolf != null) {
    parts.add('Avg SWOLF ${workout.avgSwolf}.');
  }
  if (workout.hrMin != null || workout.hrMax != null || workout.hrPeak != null) {
    final hr = [
      if (workout.hrMin != null) 'min ${workout.hrMin}',
      if (workout.hrMax != null) 'max ${workout.hrMax}',
      if (workout.hrPeak != null) 'peak ${workout.hrPeak}',
    ].join(', ');
    parts.add('HR $hr bpm (totals only; no HR stream).');
  }
  return parts.join(' ');
}

String _humanSport(int type) {
  const names = <int, String>{
    1: 'Walk',
    2: 'Run',
    3: 'Cycle',
    5: 'Indoor run',
    6: 'Pool swim',
    7: 'Indoor cycle',
    8: 'Open water',
    9: 'Elliptical',
    10: 'Rower',
    140: 'Strength',
  };
  return names[type] ?? 'Workout $type';
}

String _lapsXml(WorkoutSummary workout) {
  final segments = workout.segments;
  if (segments != null && segments.isNotEmpty) {
    final buf = StringBuffer();
    var cursor = workout.startTime;
    var distanceCursor = 0;
    final totalDist = workout.distanceM ??
        segments.fold<int>(0, (s, seg) => s + (seg.distanceM ?? 0));
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final startSec = cursor;
      final dur = seg.durationSec ?? 0;
      final endSec = dur > 0 ? startSec + dur : startSec;
      final segDist = seg.distanceM ?? 0;
      // Last segment absorbs remainder so lap distances sum to session total.
      final lapDist = i == segments.length - 1 && totalDist > distanceCursor
          ? totalDist - distanceCursor
          : segDist;
      buf.write(
        _lapXml(
          startUnix: startSec,
          durationSec: dur > 0 ? dur : (i == 0 ? workout.durationSec : 0),
          distanceM: lapDist > 0 ? lapDist : null,
          calories: i == 0 ? workout.calories : null,
          avgHr: null,
          maxHr: i == 0 ? (workout.hrMax ?? workout.hrPeak) : null,
          minHr: i == 0 ? workout.hrMin : null,
        ),
      );
      distanceCursor += lapDist;
      cursor = endSec > startSec ? endSec : cursor;
    }
    return buf.toString();
  }

  return _lapXml(
    startUnix: workout.startTime,
    durationSec: workout.durationSec,
    distanceM: workout.distanceM,
    calories: workout.calories,
    avgHr: null,
    maxHr: workout.hrMax ?? workout.hrPeak,
    minHr: workout.hrMin,
  );
}

String _lapXml({
  required int startUnix,
  required int durationSec,
  required int? distanceM,
  required int? calories,
  required int? avgHr,
  required int? maxHr,
  int? minHr,
}) {
  final dur = durationSec < 0 ? 0 : durationSec;
  final dist = distanceM != null && distanceM > 0 ? distanceM : 0;
  final start = _isoUtc(DateTime.fromMillisecondsSinceEpoch(
    startUnix * 1000,
    isUtc: true,
  ));
  final resolvedAvg = avgHr ??
      (minHr != null && maxHr != null
          ? ((minHr + maxHr) / 2).round()
          : maxHr);

  final buf = StringBuffer()
    ..writeln('      <Lap StartTime="$start">')
    ..writeln('        <TotalTimeSeconds>$dur</TotalTimeSeconds>')
    ..writeln('        <DistanceMeters>$dist</DistanceMeters>');
  if (calories != null && calories >= 0) {
    buf.writeln('        <Calories>$calories</Calories>');
  }
  if (resolvedAvg != null) {
    buf
      ..writeln('        <AverageHeartRateBpm>')
      ..writeln('          <Value>$resolvedAvg</Value>')
      ..writeln('        </AverageHeartRateBpm>');
  }
  if (maxHr != null) {
    buf
      ..writeln('        <MaximumHeartRateBpm>')
      ..writeln('          <Value>$maxHr</Value>')
      ..writeln('        </MaximumHeartRateBpm>');
  }
  buf
    ..writeln('        <Intensity>Active</Intensity>')
    ..writeln('        <TriggerMethod>Manual</TriggerMethod>')
    ..write(_trackXml(
      startUnix: startUnix,
      durationSec: dur,
      distanceM: dist,
      maxHr: maxHr,
      avgHr: resolvedAvg,
    ))
    ..writeln('      </Lap>');
  return buf.toString();
}

/// Synthetic distance stream — Strava zeros activities without trackpoint distances.
String _trackXml({
  required int startUnix,
  required int durationSec,
  required int distanceM,
  int? maxHr,
  int? avgHr,
}) {
  final points = _syntheticTrackPoints(
    startUnix: startUnix,
    durationSec: durationSec,
    distanceM: distanceM,
  );
  final buf = StringBuffer()..writeln('        <Track>');
  for (final p in points) {
    buf
      ..writeln('          <Trackpoint>')
      ..writeln('            <Time>${_isoUtc(DateTime.fromMillisecondsSinceEpoch(p.unixSec * 1000, isUtc: true))}</Time>')
      ..writeln('            <DistanceMeters>${p.distanceM.toStringAsFixed(1)}</DistanceMeters>');
    final hr = p.isEnd ? maxHr : avgHr;
    if (hr != null) {
      buf
        ..writeln('            <HeartRateBpm>')
        ..writeln('              <Value>$hr</Value>')
        ..writeln('            </HeartRateBpm>');
    }
    buf.writeln('          </Trackpoint>');
  }
  buf.writeln('        </Track>');
  return buf.toString();
}

class _TrackSample {
  const _TrackSample({
    required this.unixSec,
    required this.distanceM,
    required this.isEnd,
  });

  final int unixSec;
  final double distanceM;
  final bool isEnd;
}

/// Evenly spaced samples (~60s), always including start (0 m) and end (full).
List<_TrackSample> _syntheticTrackPoints({
  required int startUnix,
  required int durationSec,
  required int distanceM,
}) {
  final dur = durationSec <= 0 ? 1 : durationSec;
  final steps = (dur / 60).ceil().clamp(1, 120);
  final samples = <_TrackSample>[
    _TrackSample(unixSec: startUnix, distanceM: 0, isEnd: false),
  ];
  for (var i = 1; i <= steps; i++) {
    final t = (dur * i / steps).round();
    final d = distanceM * (i / steps);
    samples.add(
      _TrackSample(
        unixSec: startUnix + t,
        distanceM: d,
        isEnd: i == steps,
      ),
    );
  }
  return samples;
}

String _isoUtc(DateTime dt) {
  final u = dt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)}T'
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

String _formatPoolLengthCm(int cm) {
  if (cm >= 100 && cm % 100 == 0) return '${cm ~/ 100} m';
  if (cm >= 100) {
    final m = cm / 100.0;
    return '${m.toStringAsFixed(m.truncateToDouble() == m ? 0 : 1)} m';
  }
  return '$cm m';
}

String _escapeXml(String raw) {
  return raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
