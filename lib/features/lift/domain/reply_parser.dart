import 'package:fitness_os/features/lift/domain/planned_session.dart';

class ReplyOutcome {
  const ReplyOutcome({
    required this.actualKg,
    required this.actualReps,
    required this.failed,
    required this.unknownReply,
  });

  final double actualKg;
  final int actualReps;
  final bool failed;
  final bool unknownReply;
}

ReplyOutcome parseReply(String raw, PlannedSet plan) {
  final text = raw.trim();
  final lower = text.toLowerCase();

  if (_isDone(lower)) {
    return ReplyOutcome(
      actualKg: _roundKg(plan.plannedKg),
      actualReps: plan.plannedReps,
      failed: false,
      unknownReply: false,
    );
  }

  if (lower == 'failed' || lower.contains('fail')) {
    return ReplyOutcome(
      actualKg: _roundKg(plan.plannedKg),
      actualReps: 0,
      failed: true,
      unknownReply: false,
    );
  }

  final delta = RegExp(
    r'^([+-]\d+(?:\.\d+)?)\s*(rep|reps|kg)$',
    caseSensitive: false,
  ).firstMatch(lower);

  if (delta != null) {
    final amount = double.parse(delta.group(1)!);
    final unit = delta.group(2)!.toLowerCase();
    if (unit == 'kg') {
      return ReplyOutcome(
        actualKg: _roundKg((plan.plannedKg + amount).clamp(0, 500)),
        actualReps: plan.plannedReps,
        failed: false,
        unknownReply: false,
      );
    }
  }

  final repDelta = RegExp(r'^([+-]\d+)\s*rep').firstMatch(lower);
  if (repDelta != null) {
    final deltaReps = int.parse(repDelta.group(1)!);
    return ReplyOutcome(
      actualKg: _roundKg(plan.plannedKg),
      actualReps: (plan.plannedReps + deltaReps).clamp(0, 50),
      failed: false,
      unknownReply: false,
    );
  }

  return ReplyOutcome(
    actualKg: _roundKg(plan.plannedKg),
    actualReps: plan.plannedReps,
    failed: false,
    unknownReply: true,
  );
}

bool _isDone(String lower) =>
    lower == 'done' ||
    lower == 'ok' ||
    lower == 'yes' ||
    lower.contains('done as planned');

double _roundKg(double kg) {
  final half = (kg * 2).round() / 2;
  return half < 0 ? 0 : half;
}