import 'dart:convert';

import 'package:fitness_os/core/backend/sync_models.dart';

class ValidationResult {
  const ValidationResult.ok() : ok = true, reason = null;

  const ValidationResult.invalid(this.reason)
      : ok = false;

  final bool ok;
  final String? reason;
}

class SyncRecordValidator {
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
    if (encoded.length > 200 * 1024) {
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
    final stages = body['stages'] as List?;
    var stageSumMin = 0;
    if (stages != null) {
      for (final s in stages) {
        if (s is! Map) continue;
        final dur = s['durationMin'] as num?;
        final stage = s['stage'] as num?;
        if (dur != null && dur < 0) {
          return const ValidationResult.invalid('negative_duration');
        }
        if (stage != null && ![1, 2, 3, 4].contains(stage.toInt())) {
          return const ValidationResult.invalid('bad_stage');
        }
        if (dur != null) stageSumMin += dur.toInt();
      }
    }
    final spanMin = (endI - beginI) ~/ 60;
    if (stageSumMin > spanMin + 30) {
      return const ValidationResult.invalid('stage_sum_exceeds_span');
    }
    final score = body['sleepScore'] as num?;
    if (score != null && (score < 0 || score > 100)) {
      return const ValidationResult.invalid('sleep_score_out_of_range');
    }
    final avgHr = body['avgHr'] as num?;
    if (avgHr != null && (avgHr < 25 || avgHr > 200)) {
      return const ValidationResult.invalid('hr_out_of_range');
    }
    final spo2 = body['avgSpO2'] as num?;
    if (spo2 != null && (spo2 < 50 || spo2 > 100)) {
      return const ValidationResult.invalid('spo2_out_of_range');
    }
    final breath = body['avgBreathRate'] as num?;
    if (breath != null && (breath < 0 || breath > 60)) {
      return const ValidationResult.invalid('breath_out_of_range');
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