import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/in_session_hr_curve_host.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';

/// Racket sport session analytics: HR chart, training load/effect, recovery.
///
/// Shows:
/// - HR over time chart with zones (if samples available)
/// - Training load, aerobic/anaerobic TE, recovery time, training points
/// - HR min/max/peak
/// - Empty state if samples missing
class RacketSessionAnalytics extends StatelessWidget {
  const RacketSessionAnalytics({
    super.key,
    required this.workout,
    this.runSessionStore,
    this.preloadedStreamPoints,
    this.onAllSessions,
  });

  final WorkoutSummary workout;
  final RunSessionStore? runSessionStore;
  final List<RunStreamPoint>? preloadedStreamPoints;
  final VoidCallback? onAllSessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // HR chart (or empty state if samples missing)
        InSessionHrCurveHost(
          workout: workout,
          runSessionStore: runSessionStore,
          preloadedStreamPoints: preloadedStreamPoints,
        ),
        const SizedBox(height: 16),

        // Training metrics card (load, TE, recovery)
        if (_hasTrainingMetrics(workout)) ...[
          _TrainingMetricsCard(workout: workout),
          const SizedBox(height: 16),
        ],

        // HR ranges card
        if (_hasHr(workout)) ...[
          _HrRangesCard(workout: workout),
          const SizedBox(height: 16),
        ],

        // Session summary card
        _SessionSummaryCard(workout: workout),
        const SizedBox(height: 16),

        // Back button
        if (onAllSessions != null)
          Center(
            child: TextButton(
              onPressed: onAllSessions,
              child: const Text('← All sessions'),
            ),
          ),
      ],
    );
  }

  bool _hasTrainingMetrics(WorkoutSummary w) {
    return w.load != null ||
        w.aerobicEffect != null ||
        w.anaerobicEffect != null ||
        w.recoveryTime != null ||
        w.trainingPoints != null;
  }

  bool _hasHr(WorkoutSummary w) {
    return w.hrMin != null || w.hrMax != null || w.hrPeak != null;
  }
}

class _TrainingMetricsCard extends StatelessWidget {
  const _TrainingMetricsCard({required this.workout});

  final WorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return BpContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Training metrics',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (workout.load != null)
            _MetricRow(
              label: 'Training load',
              value: '${workout.load}',
              icon: Icons.trending_up,
              color: _loadColor(context, workout.load!),
            ),
          if (workout.aerobicEffect != null)
            _MetricRow(
              label: 'Aerobic TE',
              value: _formatTrainingEffect(workout.aerobicEffect!),
              icon: Icons.favorite,
              color: scheme.primary,
            ),
          if (workout.anaerobicEffect != null)
            _MetricRow(
              label: 'Anaerobic TE',
              value: _formatTrainingEffect(workout.anaerobicEffect!),
              icon: Icons.flash_on,
              color: scheme.secondary,
            ),
          if (workout.recoveryTime != null)
            _MetricRow(
              label: 'Recovery time',
              value: _formatRecoveryTime(workout.recoveryTime!),
              icon: Icons.schedule,
              color: scheme.tertiary,
            ),
          if (workout.trainingPoints != null)
            _MetricRow(
              label: 'Training points',
              value: '${workout.trainingPoints}',
              icon: Icons.star,
              color: scheme.primary,
            ),
        ],
      ),
    );
  }

  String _formatTrainingEffect(int wireValue) {
    // Wire value is TE × 10, so 23 → 2.3
    return (wireValue / 10.0).toStringAsFixed(1);
  }

  String _formatRecoveryTime(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours h';
    return '$hours h $mins min';
  }

  Color _loadColor(BuildContext context, int load) {
    final scheme = Theme.of(context).colorScheme;
    if (load < 50) return scheme.primary;
    if (load < 100) return scheme.secondary;
    return scheme.error;
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _HrRangesCard extends StatelessWidget {
  const _HrRangesCard({required this.workout});

  final WorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BpContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Heart rate',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (workout.hrMin != null)
            _Row(label: 'Min', value: '${workout.hrMin} bpm'),
          if (workout.hrMax != null)
            _Row(label: 'Max', value: '${workout.hrMax} bpm'),
          if (workout.hrPeak != null)
            _Row(label: 'Peak', value: '${workout.hrPeak} bpm'),
        ],
      ),
    );
  }
}

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({required this.workout});

  final WorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BpContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Session',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _Row(label: 'Start', value: _formatWhen(workout.startTime)),
          _Row(label: 'End', value: _formatWhen(workout.endTime)),
          _Row(label: 'Duration', value: _formatDuration(workout.durationSec)),
          if (workout.calories != null)
            _Row(label: 'Calories', value: '${workout.calories} kcal'),
          if (workout.distanceM != null)
            _Row(label: 'Distance', value: '${workout.distanceM} m'),
          if (workout.steps != null) _Row(label: 'Steps', value: '${workout.steps}'),
        ],
      ),
    );
  }

  String _formatWhen(int unixTimestamp) {
    return formatWorkoutTimestamp(unixTimestamp);
  }

  String _formatDuration(int seconds) {
    return formatDuration(seconds);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
