import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/workout_type_icon.dart';

/// Calm session card for sport history lists — key signals only, no charts.
class WorkoutSessionRow extends StatelessWidget {
  const WorkoutSessionRow({
    super.key,
    required this.workout,
    required this.onTap,
    this.thirdLabel = 'SWOLF',
    this.thirdValue,
    this.metaColumns,
  });

  final WorkoutSummary workout;
  final VoidCallback onTap;

  /// Third meta column label (swim SWOLF, run Calories, etc.).
  final String thirdLabel;

  /// Third meta value; defaults to [WorkoutSummary.avgSwolf] when null.
  final String? thirdValue;

  /// When set, replaces the default Distance / Time / third meta row.
  final List<({String label, String value})>? metaColumns;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final third = thirdValue ?? (workout.avgSwolf?.toString() ?? '—');
    final metas = metaColumns ??
        [
          (label: 'Distance', value: formatDistanceM(workout.distanceM)),
          (label: 'Time', value: formatDurationClock(workout.durationSec)),
          (label: thirdLabel, value: third),
        ];

    return Material(
      color: colors.bgElev,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WorkoutTypeIcon(
                    type: workout.type,
                    size: 22,
                    color: colors.ink,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workoutSessionTitle(workout),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          formatWorkoutWhen(workout.startTime),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.inkFaint,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.inkFaint, size: 22),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: colors.line),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < metas.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: _Meta(
                        label: metas[i].label,
                        value: metas[i].value,
                      ),
                    ),
                  ],
                ],
              ),
              if (workout.sessionFlag != null &&
                  workout.sessionFlag!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        workout.sessionFlag!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.amber,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.inkFaint,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
