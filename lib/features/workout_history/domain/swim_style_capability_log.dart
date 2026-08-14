/// Pure classifiers / log-line formatters for swim stroke style capability proof.
///
/// Emits owner-readable `swim-style` / `swim-style-outcome` lines after Sync.
/// Does not invent styles when the watch sends none.
library;

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/swim_stroke_label.dart';

enum SwimStyleCapabilityStatus {
  stylesLogged,
  blocked,
}

extension SwimStyleCapabilityStatusWire on SwimStyleCapabilityStatus {
  String get wireName => switch (this) {
        SwimStyleCapabilityStatus.stylesLogged => 'styles_logged',
        SwimStyleCapabilityStatus.blocked => 'blocked',
      };
}

class SwimStyleLapLog {
  const SwimStyleLapLog({
    required this.lapIndex,
    required this.styleCode,
    required this.label,
  });

  final int lapIndex;
  final int? styleCode;
  final String label;
}

class SwimStyleCapabilityOutcome {
  const SwimStyleCapabilityOutcome({
    required this.workoutNumber,
    required this.startTime,
    required this.status,
    required this.laps,
    this.reason,
  });

  final int workoutNumber;
  final int startTime;
  final SwimStyleCapabilityStatus status;
  final String? reason;
  final List<SwimStyleLapLog> laps;

  /// Per-lap lines (when any) plus a single outcome line.
  List<String> toLogLines() {
    final lines = <String>[
      for (final lap in laps)
        'swim-style number=$workoutNumber startTime=$startTime '
        'lap=${lap.lapIndex} style=${lap.styleCode ?? 'null'} '
        'label=${lap.label}',
    ];
    final reasonPart = reason == null ? '' : ' reason=$reason';
    final lapsPart = status == SwimStyleCapabilityStatus.stylesLogged
        ? ' laps=${laps.length}'
        : '';
    lines.add(
      'swim-style-outcome number=$workoutNumber startTime=$startTime '
      'status=${status.wireName}$reasonPart$lapsPart',
    );
    return lines;
  }
}

/// Classify one incoming sync swim for style capability logging.
///
/// Returns null for non-swim workouts (no capability claim).
SwimStyleCapabilityOutcome? classifySwimStyleCapability(WorkoutSummary workout) {
  if (!CanonicalSwimSession.looksLikeSwim(workout)) return null;

  final segments = workout.segments ?? const <WorkoutSegment>[];

  if (workout.segmentsCount == 0) {
    return SwimStyleCapabilityOutcome(
      workoutNumber: workout.number,
      startTime: workout.startTime,
      status: SwimStyleCapabilityStatus.blocked,
      reason: 'segments_count_zero',
      laps: const [],
    );
  }

  if (segments.isEmpty) {
    return SwimStyleCapabilityOutcome(
      workoutNumber: workout.number,
      startTime: workout.startTime,
      status: SwimStyleCapabilityStatus.blocked,
      reason: 'segments_empty',
      laps: const [],
    );
  }

  final laps = [
    for (final s in segments)
      SwimStyleLapLog(
        lapIndex: s.index,
        styleCode: s.style,
        label: swimStrokeLabel(s.style),
      ),
  ];

  final anyStyle = laps.any((l) => l.styleCode != null);
  if (!anyStyle) {
    return SwimStyleCapabilityOutcome(
      workoutNumber: workout.number,
      startTime: workout.startTime,
      status: SwimStyleCapabilityStatus.blocked,
      reason: 'all_styles_null',
      laps: laps,
    );
  }

  return SwimStyleCapabilityOutcome(
    workoutNumber: workout.number,
    startTime: workout.startTime,
    status: SwimStyleCapabilityStatus.stylesLogged,
    laps: laps,
  );
}

/// Distinct Sync-failure outcome — not a capability Pass or Blocked-empty claim.
String syncNotOkSwimStyleOutcomeLine(WorkoutSyncStatus status) {
  final wire = switch (status) {
    WorkoutSyncStatus.ok => 'ok',
    WorkoutSyncStatus.empty => 'empty',
    WorkoutSyncStatus.stuck => 'stuck',
    WorkoutSyncStatus.notReady => 'not_ready',
    WorkoutSyncStatus.error => 'error',
    WorkoutSyncStatus.busy => 'busy',
    WorkoutSyncStatus.partialBatch => 'partial_batch',
  };
  return 'swim-style-outcome status=sync_not_ok syncStatus=$wire';
}

/// Emit log lines for every incoming swim after a successful Sync merge.
void emitSwimStyleCapabilityLogs(
  List<WorkoutSummary> incoming, {
  required void Function(String message) log,
}) {
  for (final workout in incoming) {
    final outcome = classifySwimStyleCapability(workout);
    if (outcome == null) continue;
    for (final line in outcome.toLogLines()) {
      log(line);
    }
  }
}
