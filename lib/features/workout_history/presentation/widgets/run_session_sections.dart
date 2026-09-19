import 'package:flutter/material.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/domain/gt5_run_sample_parser.dart';
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
    this.workoutType = 2,
    this.store,
    this.preloadedSplits,
    this.preloadedPoints,
  });

  final int workoutNumber;

  /// Totals type (Walk=1, Outdoor Run=2, Indoor run=5) for sample-marker dispatch.
  final int workoutType;

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
    _future = _load(sessionStore, widget.workoutNumber, widget.workoutType);
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
    int workoutType,
  ) async {
    try {
      final pacePages = await store.loadPaceBlocks(workoutNumber);
      final dataPages = await store.loadDataPages(workoutNumber);
      final splits = runPaceSplitsFromPages(pacePages);
      final hrSamples = decodeRunSamplePoints(
        dataPages,
        workoutType: workoutType,
      );
      final paceSteps = runPaceSeriesFromSplits(splits);
      final points = mergeRunStreamPaceAndHr(
        hrSamples: hrSamples,
        paceSteps: paceSteps,
      );
      return _RunStreamsBundle(splits: splits, points: points);
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
            if (metrics.trainingPoints != null)
              _MetricRow('Training points', '${metrics.trainingPoints}'),
            if (metrics.maxMetRaw != null)
              _MetricRow('maxMET (raw)', '${metrics.maxMetRaw}'),
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
            if (metrics.hrZoneMinutes == null)
              Text(
                'Native zone minutes not on wire for this session '
                '(not invented from HR series).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
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
              _MetricRow(
                'Elevation gain',
                '${metrics.elevGainM!.toStringAsFixed(1)} m',
              ),
            if (metrics.elevLossM != null)
              _MetricRow(
                'Elevation loss / descent',
                '${metrics.elevLossM!.toStringAsFixed(1)} m',
              ),
            if (metrics.maxAltitudeM != null)
              _MetricRow(
                'Max altitude',
                '${metrics.maxAltitudeM!.toStringAsFixed(1)} m',
              ),
            if (metrics.minAltitudeM != null)
              _MetricRow(
                'Min altitude',
                '${metrics.minAltitudeM!.toStringAsFixed(1)} m',
              ),
            if (metrics.avgAltitudeM != null)
              _MetricRow(
                'Avg altitude',
                '${metrics.avgAltitudeM!.toStringAsFixed(1)} m',
              ),
            if (metrics.activeCalories != null)
              _MetricRow('Active calories', '${metrics.activeCalories} kcal'),
            if (metrics.avgHrBpm != null)
              _MetricRow('Avg HR', '${metrics.avgHrBpm} bpm'),
            if (metrics.vo2Max != null)
              _MetricRow('VO₂ max', metrics.vo2Max!.toStringAsFixed(1)),
            if (metrics.maxMetRaw != null && metrics.vo2Max == null)
              _MetricRow('maxMET (raw)', '${metrics.maxMetRaw}'),
            if (metrics.verticalOscillationCm != null)
              _MetricRow(
                'Vertical oscillation',
                '${metrics.verticalOscillationCm!.toStringAsFixed(1)} cm',
              ),
            if (metrics.balancePct != null)
              _MetricRow(
                'Balance (L)',
                '${metrics.balancePct!.toStringAsFixed(1)}%',
              ),
            if (metrics.gctMs == null &&
                metrics.verticalOscillationCm == null &&
                metrics.balancePct == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'GCT / VO / balance scalars missing from leftovers.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Loads Totals leftovers → fills training/form/altitude tiles + wire dump.
///
/// Fetch-verification surface: show everything we can decode from side-files
/// without inventing missing series (GCT/VO/balance graphs stay omitted).
class RunSessionEnrichmentSection extends StatefulWidget {
  const RunSessionEnrichmentSection({
    super.key,
    required this.workoutNumber,
    required this.baseMetrics,
    this.workoutType = 2,
    this.distanceM,
    this.store,
    this.preloadedLeftovers,
  });

  final int workoutNumber;
  final RunSessionMetrics baseMetrics;

  /// Totals type for sample-marker dispatch (avg HR from stream).
  final int workoutType;
  final int? distanceM;
  final RunSessionStore? store;

  /// Test seam: skip side-file IO.
  final List<LeftoverTlvBody>? preloadedLeftovers;

  @override
  State<RunSessionEnrichmentSection> createState() =>
      _RunSessionEnrichmentSectionState();
}

class _RunSessionEnrichmentSectionState
    extends State<RunSessionEnrichmentSection> {
  Future<RunSessionMetrics>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedLeftovers != null) {
      return;
    }
    final store = widget.store ?? sl<RunSessionStore>();
    _future = _load(
      store,
      widget.workoutNumber,
      widget.baseMetrics,
      workoutType: widget.workoutType,
      distanceM: widget.distanceM,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preloadedLeftovers != null) {
      final m = widget.preloadedLeftovers!.isEmpty
          ? widget.baseMetrics
          : RunSessionMetrics.fromLeftovers(
              widget.preloadedLeftovers!,
              steps: widget.baseMetrics.steps,
              distanceM: widget.distanceM,
            ).mergeSummary(widget.baseMetrics);
      return _body(m);
    }

    return FutureBuilder<RunSessionMetrics>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Loading Totals leftovers…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        return _body(snap.data ?? widget.baseMetrics);
      },
    );
  }

  Widget _body(RunSessionMetrics metrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metrics.hasThisRunTraining) ...[
          RunThisRunTrainingCard(metrics: metrics),
          const SizedBox(height: 12),
        ],
        if (metrics.hasNativeZones) ...[
          RunNativeZonesCard(metrics: metrics),
          const SizedBox(height: 12),
        ],
        if (metrics.hasFormTiles ||
            metrics.hasAltitude ||
            metrics.hasVerticalOscillation ||
            metrics.hasBalance) ...[
          RunFormTilesCard(metrics: metrics),
          const SizedBox(height: 12),
        ],
        if (metrics.decodedLeftovers.isNotEmpty)
          RunLeftoversDumpCard(rows: metrics.decodedLeftovers),
      ],
    );
  }

  static Future<RunSessionMetrics> _load(
    RunSessionStore store,
    int workoutNumber,
    RunSessionMetrics base, {
    required int workoutType,
    int? distanceM,
  }) async {
    try {
      final leftovers = await store.loadTotalsLeftovers(workoutNumber);
      if (leftovers.isEmpty) return base;
      var merged = RunSessionMetrics.fromLeftovers(
        leftovers,
        steps: base.steps,
        distanceM: distanceM,
      ).mergeSummary(base);

      // Avg HR from sample stream when present (locked vs watch avg 153).
      final dataPages = await store.loadDataPages(workoutNumber);
      final samples = decodeRunSamplePoints(
        dataPages,
        workoutType: workoutType,
      );
      final hrs = samples.map((p) => p.hrBpm).whereType<int>().toList();
      if (hrs.isNotEmpty) {
        final avg = (hrs.reduce((a, b) => a + b) / hrs.length).round();
        merged = merged.copyWith(avgHrBpm: avg);
      }
      return merged;
    } catch (_) {
      return base;
    }
  }
}

/// Raw Totals leftover probe — id, oracle name, value, hex.
class RunLeftoversDumpCard extends StatelessWidget {
  const RunLeftoversDumpCard({super.key, required this.rows});

  final List<RunLeftoverDecoded> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text(
            'Totals leftovers (fetch probe)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${rows.length} TLV(s) · oracle names · provisional scales',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        '0x${r.id.toRadixString(16)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: r.mappedToTile
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.oracleName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            r.display ??
                                (r.rawBe != null
                                    ? 'be=${r.rawBe} · ${r.rawHex}'
                                    : r.rawHex),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${r.len}B',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
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
