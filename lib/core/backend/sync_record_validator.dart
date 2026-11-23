import 'dart:convert';

import 'package:fitness_os/core/backend/sync_models.dart';

class ValidationResult {
  const ValidationResult.ok() : ok = true, reason = null;

  const ValidationResult.invalid(this.reason)
      : ok = false;

  final bool ok;
  final String? reason;
}

/// Reasons that may be cleared when sleep body is sanitized and re-queued.
const sleepSoftQuarantineReasons = <String>{
  'stage_sum_exceeds_span',
  'bad_stage',
  'spo2_out_of_range',
  'hr_out_of_range',
  'breath_out_of_range',
  'sleep_score_out_of_range',
  'negative_duration',
};

class SyncRecordValidator {
  static const maxSleepRecordBytes = 200 * 1024;
  static const stageSpanSlackMin = 30;

  static bool isSoftSleepQuarantineReason(String reason) =>
      sleepSoftQuarantineReasons.contains(reason);

  /// Drops sentinel/out-of-range enrich fields and normalizes stages for upload.
  static void sanitizeSleepBody(Map<String, dynamic> body) {
    _dropOutOfRangeEnrich(body);

    final begin = body['beginUnix'];
    final end = body['endUnix'];
    if (begin is! num || end is! num) return;
    final beginI = begin.toInt();
    final endI = end.toInt();
    if (endI <= beginI) return;
    final spanMin = (endI - beginI) ~/ 60;

    final stages = body['stages'];
    if (stages is! List || stages.isEmpty) {
      body.remove('stages');
      return;
    }

    final cleaned = <Map<String, dynamic>>[];
    for (final s in stages) {
      if (s is! Map) continue;
      final map = Map<String, dynamic>.from(s);
      final dur = map['durationMin'];
      final stage = map['stage'];
      if (dur is! num || dur < 0) continue;
      if (stage is! num || ![1, 2, 3, 4].contains(stage.toInt())) continue;
      cleaned.add(map);
    }

    if (cleaned.isEmpty) {
      body.remove('stages');
      return;
    }

    var stageSumMin =
        cleaned.fold<int>(0, (sum, s) => sum + (s['durationMin'] as num).toInt());
  if (stageSumMin > spanMin + stageSpanSlackMin) {
      if (spanMin <= 0) {
        body.remove('stages');
        return;
      }
      _scaleStagesToFit(cleaned, spanMin);
      stageSumMin =
          cleaned.fold<int>(0, (sum, s) => sum + (s['durationMin'] as num).toInt());
      if (stageSumMin > spanMin + stageSpanSlackMin) {
        body.remove('stages');
        return;
      }
    }
    body['stages'] = cleaned;
  }

  static void _dropOutOfRangeEnrich(Map<String, dynamic> body) {
    void keepIf(String key, bool Function(num v) ok) {
      final v = body[key];
      if (v is num && !ok(v)) body.remove(key);
    }

    keepIf('sleepScore', (v) => v >= 0 && v <= 100);
    keepIf('avgHr', (v) => v >= 25 && v <= 200);
    keepIf('avgSpO2', (v) => v >= 50 && v <= 100);
    keepIf('avgBreathRate', (v) => v >= 0 && v <= 60);
  }

  static void _scaleStagesToFit(List<Map<String, dynamic>> stages, int targetSum) {
    final sum =
        stages.fold<int>(0, (s, st) => s + (st['durationMin'] as num).toInt());
    if (sum <= targetSum) return;
    var allocated = 0;
    for (var i = 0; i < stages.length; i++) {
      final d = (stages[i]['durationMin'] as num).toInt();
      if (i == stages.length - 1) {
        stages[i]['durationMin'] = (targetSum - allocated).clamp(0, targetSum);
      } else {
        final scaled = ((d * targetSum) / sum).floor();
        stages[i]['durationMin'] = scaled;
        allocated += scaled;
      }
    }
  }

  static int encodedBodyBytes(Map<String, dynamic> body) =>
      utf8.encode(jsonEncode(body)).length;

  ValidationResult validate(SyncRecord r, {required DateTime now}) {
    final body = r.body;
    switch (r.kind) {
      case SyncRecordKind.workout:
        return _validateWorkout(body, now, r);
      case SyncRecordKind.sleep:
        return _validateSleep(body, now);
      case SyncRecordKind.dailyTotals:
        return _validateDailyTotals(body, now);
      case SyncRecordKind.heartRate:
        return _validateHeartRate(body);
    }
  }

  ValidationResult _tooLarge(SyncRecord r) {
    final encoded = utf8.encode(jsonEncode(r.body));
    if (encoded.length > maxSleepRecordBytes) {
      return const ValidationResult.invalid('too_large');
    }
    return const ValidationResult.ok();
  }

  ValidationResult _validateWorkout(
    Map<String, dynamic> body,
    DateTime now,
    SyncRecord r,
  ) {
    final tl = _tooLarge(r);
    if (!tl.ok) return tl;

    final start = body['startTime'];
    final end = body['endTime'];
    final durationSec = body['durationSec'];
    if (start is! num || end is! num || durationSec is! num) {
      return const ValidationResult.invalid('missing_fields');
    }
    final startI = start.toInt();
    final endI = end.toInt();
    final durI = durationSec.toInt();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final minEpoch = DateTime(2020, 1, 1).millisecondsSinceEpoch ~/ 1000;
    if (startI < minEpoch || startI > nowSec + 86400) {
      return const ValidationResult.invalid('future_time');
    }
    if (endI <= startI) {
      return const ValidationResult.invalid('end_before_start');
    }
    if (durI <= 0 || durI > 86400) {
      return const ValidationResult.invalid('negative_duration');
    }
    if (durI > (endI - startI) + 120) {
      return const ValidationResult.invalid('duration_exceeds_span');
    }
    for (final key in [
      'calories',
      'distanceM',
      'steps',
      'hrMin',
      'hrMax',
    ]) {
      final v = body[key];
      if (v != null && v is num && !v.isFinite) {
        return const ValidationResult.invalid('non_finite');
      }
      if (v != null && v is num && v < 0) {
        return const ValidationResult.invalid('negative_value');
      }
    }
    final hrMin = body['hrMin'] as num?;
    final hrMax = body['hrMax'] as num?;
    if (hrMin != null && hrMax != null) {
      if (hrMin < 25 || hrMax > 250 || hrMin > hrMax) {
        return const ValidationResult.invalid('hr_out_of_range');
      }
    }
    final cal = body['calories'] as num?;
    if (cal != null && cal > 10000) {
      return const ValidationResult.invalid('calories_out_of_range');
    }
    final dist = body['distanceM'] as num?;
    if (dist != null && dist > 500000) {
      return const ValidationResult.invalid('distance_out_of_range');
    }
    final steps = body['steps'] as num?;
    if (steps != null && steps > 200000) {
      return const ValidationResult.invalid('steps_out_of_range');
    }
    return const ValidationResult.ok();
  }

  ValidationResult _validateSleep(Map<String, dynamic> body, DateTime now) {
    final begin = body['beginUnix'] as num?;
    final end = body['endUnix'] as num?;
    if (begin == null || end == null) {
      return const ValidationResult.invalid('missing_fields');
    }
    final beginI = begin.toInt();
    final endI = end.toInt();
    if (endI <= beginI) {
      return const ValidationResult.invalid('end_before_start');
    }
    if (endI - beginI > 20 * 3600) {
      return const ValidationResult.invalid('span_too_long');
    }
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final minEpoch = DateTime(2020, 1, 1).millisecondsSinceEpoch ~/ 1000;
    if (beginI < minEpoch || beginI > nowSec + 86400) {
      return const ValidationResult.invalid('future_time');
    }
    return const ValidationResult.ok();
  }

  ValidationResult _validateDailyTotals(
    Map<String, dynamic> body,
    DateTime now,
  ) {
    final dayKey = body['dayKey'] as String?;
    if (dayKey == null || !_dayKeyPattern.hasMatch(dayKey)) {
      return const ValidationResult.invalid('bad_day_key');
    }
    final parsed = DateTime.tryParse('${dayKey}T00:00:00');
    if (parsed == null) {
      return const ValidationResult.invalid('bad_day_key');
    }
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (parsed.isAfter(tomorrow)) {
      return const ValidationResult.invalid('future_time');
    }
    final kcal = body['totalKcal'] as num?;
    if (kcal != null && kcal > 20000) {
      return const ValidationResult.invalid('calories_out_of_range');
    }
    final steps = body['steps'] as num?;
    if (steps != null && steps > 200000) {
      return const ValidationResult.invalid('steps_out_of_range');
    }
    return const ValidationResult.ok();
  }

  static final _dayKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  ValidationResult _validateHeartRate(Map<String, dynamic> body) {
    final avg = body['avgHr'] as num?;
    final max = body['maxHr'] as num?;
    if (avg == null || max == null) {
      return const ValidationResult.invalid('missing_fields');
    }
    if (avg < 25 || max > 250 || avg > max) {
      return const ValidationResult.invalid('hr_out_of_range');
    }
    return const ValidationResult.ok();
  }
}