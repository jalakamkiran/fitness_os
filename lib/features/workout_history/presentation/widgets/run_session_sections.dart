import 'package:flutter/material.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_pace_splits_table.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_session_charts.dart';

/// Loads pace-block meta + sample pages for splits / charts.
///
/// Loading → compact progress. Side-file error or empty → omit section
/// (silent; no “tiles absent” copy). Charts only when [decodeRunSamplePoints]
/// returns real points.
class RunSessionStreamsSection extends StatefulWidget {
  const RunSessionStreamsSection({
    super.key,
    required this.workoutNumber,
    this.store,
    this.preloadedSplits,
    this.preloadedPoints,
  });

  final int workoutNumber;

  /// Test seam — production uses [sl]<[RunSessionStore]>.
  final RunSessionStore? store;

  /// Test seam: skip side-file IO and render these splits immediately.
  final List<RunPaceSplit>? preloadedSplits;

  /// Test seam: skip side-file IO and render these chart points immediately.
  final List<RunStreamPoint>? preloadedPoints;

  @override
  State<RunSessionStreamsSection> createState() =>
      _RunSessionStreamsSectionState();
}

class _RunSessionStreamsSectionState extends State<RunSessionStreamsSection> {
  Future<_RunStreamsBundle>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedSplits != null || widget.preloadedPoints != null) {
      return;
    }
    final sessionStore = widget.store ?? sl<RunSessionStore>();
    _future = _load(sessionStore, widget.workoutNumber);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preloadedSplits != null || widget.preloadedPoints != null) {
      return _buildBody(
        _RunStreamsBundle(
          splits: widget.preloadedSplits ?? const [],
          points: widget.preloadedPoints ?? const [],
        ),
      );
    }

    return FutureBuilder<_RunStreamsBundle>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // Static label (not an indeterminate spinner) so widget tests can
          // pump without idle-animation hangs.
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Loading run streams…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        final data = snap.data;
        // Error / null → omit charts and splits (no zeros, no absence claim).
        if (data == null) return const SizedBox.shrink();
        return _buildBody(data);
      },
    );
  }

  Widget _buildBody(_RunStreamsBundle data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.splits.isNotEmpty) ...[
          RunPaceSplitsTable(splits: data.splits),
          if (data.points.isNotEmpty) const SizedBox(height: 12),
        ],
        if (data.points.isNotEmpty) RunSessionCharts(points: data.points),
      ],
    );
  }

  static Future<_RunStreamsBundle> _load(
    RunSessionStore store,
    int workoutNumber,
  ) async {
    try {
      final pacePages = await store.loadPaceBlocks(workoutNumber);
      final dataPages = await store.loadDataPages(workoutNumber);
      return _RunStreamsBundle(
        splits: runPaceSplitsFromPages(pacePages),
        points: decodeRunSamplePoints(dataPages),
      );
    } catch (_) {
      return const _RunStreamsBundle(splits: [], points: []);
    }
  }
}

class _RunStreamsBundle {
  const _RunStreamsBundle({
    required this.splits,
    required this.points,
  });

  final List<RunPaceSplit> splits;
  final List<RunStreamPoint> points;
}

/// This-run recovery / stress / load — omit-null section.
class RunThisRunTrainingCard extends StatelessWidget {
  const RunThisRunTrainingCard({super.key, required this.metrics});

  final RunSessionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!metrics.hasThisRunTraining) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This run',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Session recovery & training stress — not rolling Workout status',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (metrics.recoverySec != null)
              _MetricRow(
                'Recovery',
                _formatRecovery(metrics.recoverySec!),
              ),
            if (metrics.aerobicEffect != null)
              _MetricRow(
                'Aerobic stress',
                metrics.aerobicEffect!.toStringAsFixed(1),
              ),
            if (metrics.anaerobicEffect != null)
              _MetricRow(
                'Anaerobic stress',
                metrics.anaerobicEffect!.toStringAsFixed(1),
              ),
            if (metrics.sessionLoad != null)
              _MetricRow('Session load', '${metrics.sessionLoad}'),
          ],
        ),
      ),
    );
  }

  String _formatRecovery(int sec) {
    if (sec <= 0) return '—';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

/// Native HR zones only — never invent zone minutes (AE4).
class RunNativeZonesCard extends StatelessWidget {
  const RunNativeZonesCard({super.key, required this.metrics});

  final RunSessionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!metrics.hasNativeZones) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Heart rate zones',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (metrics.hrZoneType != null && metrics.hrZoneType!.isNotEmpty)
              _MetricRow('Zone type', metrics.hrZoneType!),
            if (metrics.hrZoneMinutes != null)
              for (var i = 0; i < metrics.hrZoneMinutes!.length; i++)
                _MetricRow('Zone ${i + 1}', '${metrics.hrZoneMinutes![i]} min'),
          ],
        ),
      ),
    );
  }
}

/// Form tiles — show only fetched/decoded fields (omit-null).
class RunFormTilesCard extends StatelessWidget {
  const RunFormTilesCard({super.key, required this.metrics});

  final RunSessionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!metrics.hasFormTiles) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Form',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (metrics.cadenceSpm != null)
              _MetricRow('Cadence', '${metrics.cadenceSpm} spm'),
            if (metrics.steps != null)
              _MetricRow('Steps', '${metrics.steps}'),
            if (metrics.strideCm != null)
              _MetricRow('Avg stride', '${metrics.strideCm} cm'),
            if (metrics.gctMs != null)
              _MetricRow('Ground contact', '${metrics.gctMs} ms'),
            if (metrics.elevGainM != null)
              _MetricRow('Elevation gain', '${metrics.elevGainM} m'),
            if (metrics.vo2Max != null)
              _MetricRow('VO₂ max', metrics.vo2Max!.toStringAsFixed(1)),
            // Invent-guard: VO/balance only when decoded (separate from form
            // list promotion — still gated on non-null).
            if (metrics.verticalOscillationMm != null)
              _MetricRow(
                'Vertical oscillation',
                '${metrics.verticalOscillationMm!.toStringAsFixed(1)} mm',
              ),
            if (metrics.balancePct != null)
              _MetricRow(
                'Balance',
                '${metrics.balancePct!.toStringAsFixed(0)}%',
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
