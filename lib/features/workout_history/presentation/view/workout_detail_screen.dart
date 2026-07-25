import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';

/// Session detail entry point.
///
/// Full Pace/SWOLF/strokes charts live on the swim-charts track — this screen
/// is the navigable shell so the Workouts list can push detail without
/// duplicating that stack.
class WorkoutDetailScreen extends StatelessWidget {
  const WorkoutDetailScreen({super.key, required this.workout});

  final WorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text('${workoutTypeLabel(workout.type)} · #${workout.number}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            formatWorkoutWhen(workout.startTime),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.inkFaint,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),
          _MetaGrid(
            distance: formatDistanceM(workout.distanceM),
            duration: formatDurationClock(workout.durationSec),
            swolf: workout.avgSwolf?.toString() ?? '—',
          ),
          const SizedBox(height: 20),
          Text(
            'Session charts and diagnoses open here after sync enrichment. '
            'The Workouts list stays chart-free.',
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.inkDim),
          ),
        ],
      ),
    );
  }
}

class _MetaGrid extends StatelessWidget {
  const _MetaGrid({
    required this.distance,
    required this.duration,
    required this.swolf,
  });

  final String distance;
  final String duration;
  final String swolf;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    Widget cell(String label, String value) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.inkFaint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          Expanded(child: cell('Distance', distance)),
          Expanded(child: cell('Time', duration)),
          Expanded(child: cell('SWOLF', swolf)),
        ],
      ),
    );
  }
}
