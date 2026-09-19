import 'dart:convert';

import 'package:fitness_os/core/huawei/huawei_link.dart';

/// Decoded this-run tiles for Outdoor/Indoor Run detail (U4).
///
/// Lean [WorkoutSummary] only carries [steps] today. Named tiles are filled
/// from Totals leftovers via [RunSessionMetrics.fromLeftovers] using
/// community-oracle tag IDs locked vs GT5 watch recap (#60). Never invent zeros.
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
    this.elevLossM,
    this.maxAltitudeM,
    this.minAltitudeM,
    this.avgAltitudeM,
    this.vo2Max,
    this.maxMetRaw,
    this.verticalOscillationCm,
    this.balancePct,
    this.trainingPoints,
    this.activeCalories,
    this.avgHrBpm,
    this.decodedLeftovers = const [],
  });

  /// Session recovery duration in seconds (from wire minutes × 60).
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

  /// Elevation gain/loss in metres (wire ÷10 — locked vs watch 2.7 / 5.4).
  final double? elevGainM;
  final double? elevLossM;

  /// Altitude in metres (wire ÷10 — locked vs watch 911.6 / 909.0).
  final double? maxAltitudeM;
  final double? minAltitudeM;
  final double? avgAltitudeM;
  final double? vo2Max;

  /// Raw maxMET tag (`0x10`) — scale not locked; shown in dump.
  final int? maxMetRaw;

  /// Vertical oscillation in cm (0xe7 type 0x4b — locked vs watch 10.2 cm).
  final double? verticalOscillationCm;

  /// Left-foot balance % (0xe7 type 0x4a — locked vs watch L 50.1).
  final double? balancePct;
  final int? trainingPoints;

  /// Active calories kcal (0xe7 type 0xaf ÷1000 — locked vs watch 158).
  final int? activeCalories;
  final int? avgHrBpm;

  /// Every leftover with oracle name + raw/display for fetch probe.
  final List<RunLeftoverDecoded> decodedLeftovers;

  /// Map from lean [WorkoutSummary]. Enrichment comes from [fromLeftovers].
  factory RunSessionMetrics.fromSummary(WorkoutSummary w) {
    final stride = (w.distanceM != null &&
            w.steps != null &&
            w.distanceM! > 0 &&
            w.steps! > 0)
        ? ((w.distanceM! / w.steps!) * 100).round()
        : null;
    return RunSessionMetrics(steps: w.steps, strideCm: stride);
  }

  /// Decode Totals leftover TLVs. Scales locked vs watch #60 recap where noted.
  factory RunSessionMetrics.fromLeftovers(
    List<LeftoverTlvBody> bodies, {
    int? steps,
    int? distanceM,
  }) {
    int? recoverySec;
    double? aerobicEffect;
    double? anaerobicEffect;
    int? sessionLoad;
    String? hrZoneType;
    double? elevGainM;
    double? elevLossM;
    double? maxAltitudeM;
    double? minAltitudeM;
    int? maxMetRaw;
    int? trainingPoints;
    int? gctMs;
    double? verticalOscillationCm;
    double? balancePct;
    int? activeCalories;
    final decoded = <RunLeftoverDecoded>[];

    for (final body in bodies) {
      final raw = _decodeBase64(body.bodyBase64);
      final be = raw.isNotEmpty && raw.length <= 4 ? _readBeInt(raw) : null;
      final oracle = _oracleName(body.id);
      String? display;
      var mapped = false;

      switch (body.id) {
        case 0x0b: // elevationGain ÷10 → m (27 → 2.7)
          if (be != null) {
            elevGainM = be / 10.0;
            display = '${elevGainM!.toStringAsFixed(1)} m';
            mapped = true;
          }
        case 0x0d: // workoutLoad
          if (be != null) {
            sessionLoad = be;
            display = '$be';
            mapped = true;
          }
        case 0x0e: // aerobicEffect ÷10 (23 → 2.3)
          if (be != null) {
            aerobicEffect = be / 10.0;
            display = aerobicEffect!.toStringAsFixed(1);
            mapped = true;
          }
        case 0x10: // maxMET — raw until VO₂ scale locked
          if (be != null) {
            maxMetRaw = be;
            display = 'raw $be (VO₂ scale open)';
            mapped = true;
          }
        case 0x11: // recoveryTime minutes (1260 → 21 h)
          if (be != null) {
            recoverySec = be * 60;
            display = _formatRecoveryDisplay(recoverySec!);
            mapped = true;
          }
        case 0x1b: // elevationLoss ÷10 → m (54 → 5.4)
          if (be != null) {
            elevLossM = be / 10.0;
            display = '${elevLossM!.toStringAsFixed(1)} m';
            mapped = true;
          }
        case 0x1c: // maxAltitude ÷10 → m (9116 → 911.6)
          if (be != null) {
            maxAltitudeM = be / 10.0;
            display = '${maxAltitudeM!.toStringAsFixed(1)} m';
            mapped = true;
          }
        case 0x1d: // minAltitude ÷10 → m (9090 → 909.0)
          if (be != null) {
            minAltitudeM = be / 10.0;
            display = '${minAltitudeM!.toStringAsFixed(1)} m';
            mapped = true;
          }
        case 0x20: // anaerobicEffect ÷10 (17 → 1.7)
          if (be != null) {
            anaerobicEffect = be / 10.0;
            display = anaerobicEffect!.toStringAsFixed(1);
            mapped = true;
          }
        case 0x24: // hrZoneType
          if (be != null) {
            hrZoneType = '$be';
            display = 'type $be';
            mapped = true;
          }
        case 0x63: // trainingPoints
          if (be != null) {
            trainingPoints = be;
            display = '$be';
            mapped = true;
          }
        case 0xe7: // typed ASCII form blobs
          final parsed = _parseE7FormBlob(raw);
          if (parsed != null) {
            display = parsed.display;
            mapped = true;
            switch (parsed.kind) {
              case _E7Kind.gctMs:
                gctMs = parsed.intValue;
              case _E7Kind.verticalOscillationCm:
                verticalOscillationCm = parsed.doubleValue;
              case _E7Kind.balancePct:
                balancePct = parsed.doubleValue;
              case _E7Kind.activeCalories:
                activeCalories = parsed.intValue;
              case _E7Kind.other:
                mapped = false;
            }
          }
        default:
          break;
      }

      decoded.add(
        RunLeftoverDecoded(
          id: body.id,
          len: body.len,
          oracleName: oracle,
          rawHex: raw.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          rawBe: be,
          display: display,
          mappedToTile: mapped,
        ),
      );
    }

    final stride = (distanceM != null &&
            steps != null &&
            distanceM > 0 &&
            steps > 0)
        ? ((distanceM / steps) * 100).round()
        : null;

    double? avgAltitudeM;
    if (maxAltitudeM != null && minAltitudeM != null) {
      avgAltitudeM = (maxAltitudeM + minAltitudeM) / 2.0;
    }

    return RunSessionMetrics(
      steps: steps,
      strideCm: stride,
      recoverySec: recoverySec,
      aerobicEffect: aerobicEffect,
      anaerobicEffect: anaerobicEffect,
      sessionLoad: sessionLoad,
      hrZoneType: hrZoneType,
      elevGainM: elevGainM,
      elevLossM: elevLossM,
      maxAltitudeM: maxAltitudeM,
      minAltitudeM: minAltitudeM,
      avgAltitudeM: avgAltitudeM,
      maxMetRaw: maxMetRaw,
      trainingPoints: trainingPoints,
      gctMs: gctMs,
      verticalOscillationCm: verticalOscillationCm,
      balancePct: balancePct,
      activeCalories: activeCalories,
      decodedLeftovers: decoded,
    );
  }

  RunSessionMetrics copyWith({
    int? recoverySec,
    double? aerobicEffect,
    double? anaerobicEffect,
    int? sessionLoad,
    String? hrZoneType,
    List<int>? hrZoneMinutes,
    int? cadenceSpm,
    int? steps,
    int? strideCm,
    int? gctMs,
    double? elevGainM,
    double? elevLossM,
    double? maxAltitudeM,
    double? minAltitudeM,
    double? avgAltitudeM,
    double? vo2Max,
    int? maxMetRaw,
    double? verticalOscillationCm,
    double? balancePct,
    int? trainingPoints,
    int? activeCalories,
    int? avgHrBpm,
    List<RunLeftoverDecoded>? decodedLeftovers,
  }) {
    return RunSessionMetrics(
      recoverySec: recoverySec ?? this.recoverySec,
      aerobicEffect: aerobicEffect ?? this.aerobicEffect,
      anaerobicEffect: anaerobicEffect ?? this.anaerobicEffect,
      sessionLoad: sessionLoad ?? this.sessionLoad,
      hrZoneType: hrZoneType ?? this.hrZoneType,
      hrZoneMinutes: hrZoneMinutes ?? this.hrZoneMinutes,
      cadenceSpm: cadenceSpm ?? this.cadenceSpm,
      steps: steps ?? this.steps,
      strideCm: strideCm ?? this.strideCm,
      gctMs: gctMs ?? this.gctMs,
      elevGainM: elevGainM ?? this.elevGainM,
      elevLossM: elevLossM ?? this.elevLossM,
      maxAltitudeM: maxAltitudeM ?? this.maxAltitudeM,
      minAltitudeM: minAltitudeM ?? this.minAltitudeM,
      avgAltitudeM: avgAltitudeM ?? this.avgAltitudeM,
      vo2Max: vo2Max ?? this.vo2Max,
      maxMetRaw: maxMetRaw ?? this.maxMetRaw,
      verticalOscillationCm:
          verticalOscillationCm ?? this.verticalOscillationCm,
      balancePct: balancePct ?? this.balancePct,
      trainingPoints: trainingPoints ?? this.trainingPoints,
      activeCalories: activeCalories ?? this.activeCalories,
      avgHrBpm: avgHrBpm ?? this.avgHrBpm,
      decodedLeftovers: decodedLeftovers ?? this.decodedLeftovers,
    );
  }

  RunSessionMetrics mergeSummary(RunSessionMetrics lean) {
    return RunSessionMetrics(
      recoverySec: recoverySec ?? lean.recoverySec,
      aerobicEffect: aerobicEffect ?? lean.aerobicEffect,
      anaerobicEffect: anaerobicEffect ?? lean.anaerobicEffect,
      sessionLoad: sessionLoad ?? lean.sessionLoad,
      hrZoneType: hrZoneType ?? lean.hrZoneType,
      hrZoneMinutes: hrZoneMinutes ?? lean.hrZoneMinutes,
      cadenceSpm: cadenceSpm ?? lean.cadenceSpm,
      steps: steps ?? lean.steps,
      strideCm: strideCm ?? lean.strideCm,
      gctMs: gctMs ?? lean.gctMs,
      elevGainM: elevGainM ?? lean.elevGainM,
      elevLossM: elevLossM ?? lean.elevLossM,
      maxAltitudeM: maxAltitudeM ?? lean.maxAltitudeM,
      minAltitudeM: minAltitudeM ?? lean.minAltitudeM,
      avgAltitudeM: avgAltitudeM ?? lean.avgAltitudeM,
      vo2Max: vo2Max ?? lean.vo2Max,
      maxMetRaw: maxMetRaw ?? lean.maxMetRaw,
      verticalOscillationCm:
          verticalOscillationCm ?? lean.verticalOscillationCm,
      balancePct: balancePct ?? lean.balancePct,
      trainingPoints: trainingPoints ?? lean.trainingPoints,
      activeCalories: activeCalories ?? lean.activeCalories,
      avgHrBpm: avgHrBpm ?? lean.avgHrBpm,
      decodedLeftovers:
          decodedLeftovers.isNotEmpty ? decodedLeftovers : lean.decodedLeftovers,
    );
  }

  bool get hasThisRunTraining =>
      recoverySec != null ||
      aerobicEffect != null ||
      anaerobicEffect != null ||
      sessionLoad != null ||
      trainingPoints != null;

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
      elevLossM != null ||
      vo2Max != null ||
      maxMetRaw != null ||
      activeCalories != null ||
      avgHrBpm != null;

  bool get hasAltitude =>
      maxAltitudeM != null || minAltitudeM != null || avgAltitudeM != null;

  bool get hasVerticalOscillation => verticalOscillationCm != null;
  bool get hasBalance => balancePct != null;
  bool get hasVo2 => vo2Max != null;
  bool get hasNativeZoneMinutes =>
      hrZoneMinutes != null && hrZoneMinutes!.isNotEmpty;
}

/// One Totals leftover row for the fetch-probe dump.
class RunLeftoverDecoded {
  const RunLeftoverDecoded({
    required this.id,
    required this.len,
    required this.oracleName,
    required this.rawHex,
    this.rawBe,
    this.display,
    this.mappedToTile = false,
  });

  final int id;
  final int len;
  final String oracleName;
  final String rawHex;
  final int? rawBe;
  final String? display;
  final bool mappedToTile;
}

enum _E7Kind {
  gctMs,
  verticalOscillationCm,
  balancePct,
  activeCalories,
  other,
}

class _E7Parsed {
  const _E7Parsed({
    required this.kind,
    required this.display,
    this.intValue,
    this.doubleValue,
  });
  final _E7Kind kind;
  final String display;
  final int? intValue;
  final double? doubleValue;
}

/// `0xe7` form: `68 04 11 e1 ca <type> 69 <len> <ascii>`.
_E7Parsed? _parseE7FormBlob(List<int> raw) {
  if (raw.length < 9) return null;
  if (raw[0] != 0x68 || raw[1] != 0x04 || raw[2] != 0x11 || raw[3] != 0xe1) {
    return null;
  }
  if (raw[4] != 0xca || raw[6] != 0x69) return null;
  final type = raw[5];
  final len = raw[7];
  if (8 + len > raw.length) return null;
  final text = String.fromCharCodes(raw.sublist(8, 8 + len));
  switch (type) {
    case 0x43: // 'C' GCT ms — locked 290
      final v = int.tryParse(text);
      if (v == null) return null;
      return _E7Parsed(kind: _E7Kind.gctMs, display: 'GCT $v ms', intValue: v);
    case 0x4a: // 'J' balance L% — locked 50.07
      final v = double.tryParse(text);
      if (v == null) return null;
      return _E7Parsed(
        kind: _E7Kind.balancePct,
        display: 'balance L ${v.toStringAsFixed(1)}%',
        doubleValue: v,
      );
    case 0x4b: // 'K' VO cm — locked 10.2
      final v = double.tryParse(text);
      if (v == null) return null;
      return _E7Parsed(
        kind: _E7Kind.verticalOscillationCm,
        display: 'VO ${v.toStringAsFixed(1)} cm',
        doubleValue: v,
      );
    case 0xaf: // active calories ×1000 — locked 158000 → 158
      final v = int.tryParse(text);
      if (v == null) return null;
      final kcal = v >= 1000 ? (v / 1000).round() : v;
      return _E7Parsed(
        kind: _E7Kind.activeCalories,
        display: 'active $kcal kcal',
        intValue: kcal,
      );
    default:
      return _E7Parsed(
        kind: _E7Kind.other,
        display: 'type 0x${type.toRadixString(16)}=$text',
      );
  }
}

String _oracleName(int id) {
  const names = <int, String>{
    0x0a: 'unknown_0x0a',
    0x0b: 'elevationGain',
    0x0d: 'workoutLoad',
    0x0e: 'aerobicEffect',
    0x0f: 'unknown_0x0f',
    0x10: 'maxMET',
    0x11: 'recoveryTime',
    0x1b: 'elevationLoss',
    0x1c: 'maxAltitude',
    0x1d: 'minAltitude',
    0x20: 'anaerobicEffect',
    0x21: 'unknown_0x21',
    0x22: 'unknown_0x22',
    0x23: 'unknown_0x23',
    0x24: 'hrZoneType',
    0x48: 'unknown_0x48',
    0x49: 'unknown_0x49',
    0x4d: 'unknown_0x4d',
    0x4e: 'unknown_0x4e',
    0x4f: 'unknown_0x4f',
    0x5d: 'algType',
    0x63: 'trainingPoints',
    0x66: 'recoveryHeartRates',
    0xe7: 'formAscii_0xe7',
  };
  return names[id] ?? 'tag_0x${id.toRadixString(16)}';
}

String _formatRecoveryDisplay(int sec) {
  if (sec <= 0) return '0';
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
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

/// Decoded in-run sample point for pace / HR charts.
class RunStreamPoint {
  const RunStreamPoint({
    required this.offsetSec,
    this.paceSecPerKm,
    this.hrBpm,
    this.cadenceSpm,
  });

  final int offsetSec;
  final double? paceSecPerKm;
  final int? hrBpm;

  /// Steps/min from GT5 sample byte3 when in a plausible cadence band.
  final int? cadenceSpm;
}

/// Build split rows from pace-block page scalars and nested `0x83` bodies.
///
/// GT5 Walk/Run `0x83` (locked vs watch Split data for #60):
/// - tag5 (flag) `0` = km / partial split; `1` = other markers (skip)
/// - tag6 = pace sec/km (for full km also = split time)
/// - tag9 present → distance in 0.1 m (7900 → 790 m); absent → 1000 m
List<RunPaceSplit> runPaceSplitsFromPages(List<PeeledPageBodies> pages) {
  final out = <RunPaceSplit>[];
  for (final page in pages) {
    if (page.distanceM != null || page.paceSec != null) {
      out.add(
        RunPaceSplit(
          index: page.index,
          distanceM: page.distanceM,
          paceSec: page.paceSec,
        ),
      );
    }
    for (final body in page.bodies) {
      if (body.id != 0x83) continue;
      final split = _paceSplitFrom83(body, out.length);
      if (split != null) out.add(split);
    }
  }
  out.sort((a, b) => a.index.compareTo(b.index));
  return out;
}

RunPaceSplit? _paceSplitFrom83(LeftoverTlvBody body, int fallbackIndex) {
  final raw = _decodeBase64(body.bodyBase64);
  if (raw.isEmpty) return null;
  final fields = _decodeHuaweiTlvs(raw);
  int? flag;
  int? paceSec;
  int? distanceFromTag9;
  for (final t in fields) {
    switch (t.tag) {
      case 0x05:
        if (t.value.length <= 2) flag = _readBeInt(t.value);
      case 0x06:
        if (t.value.length <= 4) paceSec = _readBeInt(t.value);
      case 0x09:
        // 0.1 m units (7900 → 790 m) — locked vs watch partial 0.79 km.
        if (t.value.length <= 4) {
          final rawDist = _readBeInt(t.value);
          if (rawDist != null && rawDist > 0) {
            distanceFromTag9 = rawDist ~/ 10;
          }
        }
    }
  }
  // flag==1 rows are not km splits (locked vs #60: 608 / 942 ignored).
  if (flag != null && flag != 0) return null;
  if (paceSec == null || paceSec <= 0) return null;
  // Plausible sec/km band (~2:00–20:00).
  if (paceSec < 120 || paceSec > 1200) return null;
  final distanceM = distanceFromTag9 ?? 1000;
  if (distanceM < 50 || distanceM > 5000) return null;
  return RunPaceSplit(
    index: fallbackIndex,
    distanceM: distanceM,
    paceSec: paceSec,
  );
}

/// Pace series from locked splits (step function over elapsed split time).
///
/// Sample-stream u16 values look like 0.1 s/km paces but are time-misaligned
/// vs HR on #60 — do not chart them until catalog-locked. Splits are locked.
List<RunStreamPoint> runPaceSeriesFromSplits(List<RunPaceSplit> splits) {
  if (splits.isEmpty) return const [];
  final out = <RunStreamPoint>[];
  var t = 0;
  for (final s in splits) {
    final dist = s.distanceM;
    final pace = s.paceSec;
    if (dist == null || dist <= 0 || pace == null || pace <= 0) continue;
    final elapsed = dist >= 1000
        ? pace
        : (pace * dist / 1000.0).round().clamp(1, 24 * 3600);
    // One point at bucket start + end so the chart holds the step.
    out.add(RunStreamPoint(offsetSec: t, paceSecPerKm: pace.toDouble()));
    t += elapsed;
    out.add(RunStreamPoint(offsetSec: t, paceSecPerKm: pace.toDouble()));
  }
  return out;
}

/// Merge HR (and optional cadence) samples with split-derived pace steps.
List<RunStreamPoint> mergeRunStreamPaceAndHr({
  required List<RunStreamPoint> hrSamples,
  required List<RunStreamPoint> paceSteps,
}) {
  if (hrSamples.isEmpty) return paceSteps;
  if (paceSteps.isEmpty) return hrSamples;

  double? paceAt(int offsetSec) {
    double? last;
    for (final p in paceSteps) {
      if (p.offsetSec > offsetSec) break;
      if (p.paceSecPerKm != null) last = p.paceSecPerKm;
    }
    return last ?? paceSteps.first.paceSecPerKm;
  }

  return [
    for (final s in hrSamples)
      RunStreamPoint(
        offsetSec: s.offsetSec,
        paceSecPerKm: paceAt(s.offsetSec),
        hrBpm: s.hrBpm,
        cadenceSpm: s.cadenceSpm,
      ),
  ];
}

/// Decode GT5 WorkoutData sample streams (`0x05` bodies) into chart points.
///
/// Wire record (8 bytes): `00 00 23 <cadence?> <hr> 00 <u16>` at ~5 s.
/// HR from byte4 is locked vs Totals min/max. Pace comes from
/// [runPaceSeriesFromSplits] — sample u16 is not charted yet.
///
/// Swim/strength in-session curves use the type-gated HR lock helper instead —
/// do not call this from those hosts (it is the 0x23 run walk, not a type gate).
List<RunStreamPoint> decodeRunSamplePoints(List<PeeledPageBodies> pages) {
  return decodeGt5EightByteHrRecords(pages, marker: 0x23);
}

/// Walk leftover `0x05` bodies as 8-byte `00 00 <marker> …` HR/cadence records.
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

  const intervalSec = 5;
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
          offsetSec: sampleIndex * intervalSec,
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

class _Tlv {
  const _Tlv(this.tag, this.value);
  final int tag;
  final List<int> value;
}

List<_Tlv> _decodeHuaweiTlvs(List<int> buf) {
  final out = <_Tlv>[];
  var i = 0;
  while (i < buf.length) {
    final tag = buf[i++];
    if (i >= buf.length) break;
    var length = 0;
    var guards = 0;
    while (i < buf.length) {
      final b = buf[i++];
      length = (length << 7) | (b & 0x7f);
      guards++;
      if ((b & 0x80) == 0) break;
      if (guards > 5) return out;
    }
    if (i + length > buf.length) break;
    out.add(_Tlv(tag, buf.sublist(i, i + length)));
    i += length;
  }
  return out;
}

int? _readBeInt(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > 4) return null;
  var v = 0;
  for (final b in bytes) {
    v = (v << 8) | (b & 0xff);
  }
  return v;
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

/// Firstbeat-style TE band copy for product UI (not a medical claim).
String teBandHint(double te, {bool anaerobic = false}) {
  if (te < 1.0) return anaerobic ? 'Negligible anaerobic' : 'Recovery band';
  if (te < 2.0) return anaerobic ? 'Light anaerobic' : 'Easy maintain';
  if (te < 3.0) return anaerobic ? 'Light anaerobic' : 'Maintain band';
  if (te < 4.0) return anaerobic ? 'Developing anaerobic' : 'Improving';
  return anaerobic ? 'High anaerobic' : 'Highly improving';
}

class AnnotatedRunSplit {
  const AnnotatedRunSplit({
    required this.split,
    required this.index,
    required this.elapsedSec,
    required this.isWalk,
    required this.isFastest,
  });

  final RunPaceSplit split;
  final int index;
  final int elapsedSec;
  final bool isWalk;
  final bool isFastest;
}

/// Tag walk/fastest without inventing pace — uses present paceSec only.
List<AnnotatedRunSplit> annotateRunSplits(List<RunPaceSplit> splits) {
  final chartable =
      splits.where((s) => s.hasDistanceOrPace).toList(growable: false);
  if (chartable.isEmpty) return const [];

  final paces = chartable
      .map((s) => s.paceSec)
      .whereType<int>()
      .where((p) => p > 0)
      .toList()
    ..sort();
  final median = paces.isEmpty ? null : paces[paces.length ~/ 2];

  final walkFlags = <bool>[];
  for (final s in chartable) {
    final pace = s.paceSec;
    final isWalk = pace != null &&
        pace > 0 &&
        (pace >= 540 || (median != null && pace >= (median * 1.35).round()));
    walkFlags.add(isWalk);
  }

  var fastestIdx = -1;
  var fastestPace = 1 << 30;
  for (var i = 0; i < chartable.length; i++) {
    final p = chartable[i].paceSec;
    if (p == null || p <= 0 || walkFlags[i]) continue;
    if (p < fastestPace) {
      fastestPace = p;
      fastestIdx = i;
    }
  }

  var elapsed = 0;
  final out = <AnnotatedRunSplit>[];
  for (var i = 0; i < chartable.length; i++) {
    final s = chartable[i];
    final pace = s.paceSec;
    final dist = s.distanceM ?? 0;
    if (pace != null && pace > 0 && dist > 0) {
      elapsed += (pace * (dist / 1000.0)).round();
    } else if (pace != null && pace > 0) {
      elapsed += pace;
    }
    out.add(
      AnnotatedRunSplit(
        split: s,
        index: i,
        elapsedSec: elapsed,
        isWalk: walkFlags[i],
        isFastest: i == fastestIdx,
      ),
    );
  }
  return out;
}

/// True when a later split looks like a walk cool-down vs earlier run km.
bool detectRunWalkTransition(List<RunPaceSplit> splits) {
  final annotated = annotateRunSplits(splits);
  if (annotated.length < 2) return false;
  final hasRun = annotated.any((a) => !a.isWalk);
  final hasWalk = annotated.any((a) => a.isWalk);
  return hasRun && hasWalk;
}

