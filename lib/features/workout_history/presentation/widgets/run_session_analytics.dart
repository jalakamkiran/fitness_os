import 'dart:math' as math;

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/strength_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_pace_splits_table.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_session_charts.dart';

/// Product Run/Walk session body — mirrors `docs/design/run-analytics.html`.
///
/// Omit-null / invent-guard: no wire dump, no invented zone minutes or form
/// series. Sleep / feel stay placeholders until those pipes exist.
class RunSessionAnalytics extends StatefulWidget {
  const RunSessionAnalytics({
    super.key,
    required this.workout,
    this.runSessionStore,
    this.preloadedPaceSplits,
    this.preloadedStreamPoints,
    this.preloadedLeftovers,
    this.onExport,
    this.exportBusy = false,
    this.onAllSessions,
  });

  final WorkoutSummary workout;
  final RunSessionStore? runSessionStore;
  final List<RunPaceSplit>? preloadedPaceSplits;
  final List<RunStreamPoint>? preloadedStreamPoints;
  final List<LeftoverTlvBody>? preloadedLeftovers;
  final VoidCallback? onExport;
  final bool exportBusy;
  final VoidCallback? onAllSessions;

  @override
  State<RunSessionAnalytics> createState() => _RunSessionAnalyticsState();
}

class _RunSessionAnalyticsState extends State<RunSessionAnalytics> {
  Future<_RunProductBundle>? _future;

  @override
  void initState() {
    super.initState();
    if (_hasPreload) return;
    final store = widget.runSessionStore ?? sl<RunSessionStore>();
    _future = _RunProductBundle.load(
      store: store,
      workout: widget.workout,
    );
  }

  bool get _hasPreload =>
      widget.preloadedPaceSplits != null ||
      widget.preloadedStreamPoints != null ||
      widget.preloadedLeftovers != null;

  _RunProductBundle get _preloaded {
    final base = RunSessionMetrics.fromSummary(widget.workout);
    final leftovers = widget.preloadedLeftovers ?? const <LeftoverTlvBody>[];
    final metrics = leftovers.isEmpty
        ? base
        : RunSessionMetrics.fromLeftovers(
            leftovers,
            steps: base.steps,
            distanceM: widget.workout.distanceM,
          ).mergeSummary(base);
    final splits = widget.preloadedPaceSplits ?? const <RunPaceSplit>[];
    final points = widget.preloadedStreamPoints ?? const <RunStreamPoint>[];
    return _RunProductBundle(
      metrics: _withStreamCadence(metrics, points),
      splits: splits,
      points: points,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPreload) {
      return _RunProductBody(
        workout: widget.workout,
        bundle: _preloaded,
        onExport: widget.onExport,
        exportBusy: widget.exportBusy,
        onAllSessions: widget.onAllSessions,
      );
    }
    return FutureBuilder<_RunProductBundle>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Loading session…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: FathomColors.of(context).inkDim,
                  ),
            ),
          );
        }
        return _RunProductBody(
          workout: widget.workout,
          bundle: snap.data ??
              _RunProductBundle(
                metrics: RunSessionMetrics.fromSummary(widget.workout),
                splits: const [],
                points: const [],
              ),
          onExport: widget.onExport,
          exportBusy: widget.exportBusy,
          onAllSessions: widget.onAllSessions,
        );
      },
    );
  }
}

RunSessionMetrics _withStreamCadence(
  RunSessionMetrics metrics,
  List<RunStreamPoint> points,
) {
  if (metrics.cadenceSpm != null || points.isEmpty) return metrics;
  final vals = points
      .map((p) => p.cadenceSpm)
      .whereType<int>()
      .where((c) => c > 0)
      .toList();
  if (vals.isEmpty) return metrics;
  final avg = (vals.reduce((a, b) => a + b) / vals.length).round();
  return metrics.copyWith(cadenceSpm: avg);
}

class _RunProductBundle {
  const _RunProductBundle({
    required this.metrics,
    required this.splits,
    required this.points,
  });

  final RunSessionMetrics metrics;
  final List<RunPaceSplit> splits;
  final List<RunStreamPoint> points;

  static Future<_RunProductBundle> load({
    required RunSessionStore store,
    required WorkoutSummary workout,
  }) async {
    final base = RunSessionMetrics.fromSummary(workout);
    try {
      final leftovers = await store.loadTotalsLeftovers(workout.number);
      final pacePages = await store.loadPaceBlocks(workout.number);
      final dataPages = await store.loadDataPages(workout.number);
      final metrics = leftovers.isEmpty
          ? base
          : RunSessionMetrics.fromLeftovers(
              leftovers,
              steps: base.steps,
              distanceM: workout.distanceM,
            ).mergeSummary(base);
      final splits = runPaceSplitsFromPages(pacePages);
      final hrSamples = decodeRunSamplePoints(dataPages);
      final paceSteps = runPaceSeriesFromSplits(splits);
      final points = mergeRunStreamPaceAndHr(
        hrSamples: hrSamples,
        paceSteps: paceSteps,
      );
      var enriched = _withStreamCadence(metrics, points);
      final hrs = hrSamples.map((p) => p.hrBpm).whereType<int>().toList();
      if (enriched.avgHrBpm == null && hrs.isNotEmpty) {
        final avg = (hrs.reduce((a, b) => a + b) / hrs.length).round();
        enriched = enriched.copyWith(avgHrBpm: avg);
      }
      return _RunProductBundle(
        metrics: enriched,
        splits: splits,
        points: points,
      );
    } catch (_) {
      return _RunProductBundle(
        metrics: base,
        splits: const [],
        points: const [],
      );
    }
  }
}

class _RunProductBody extends StatelessWidget {
  const _RunProductBody({
    required this.workout,
    required this.bundle,
    this.onExport,
    this.exportBusy = false,
    this.onAllSessions,
  });

  final WorkoutSummary workout;
  final _RunProductBundle bundle;
  final VoidCallback? onExport;
  final bool exportBusy;
  final VoidCallback? onAllSessions;

  @override
  Widget build(BuildContext context) {
    final metrics = bundle.metrics;
    final cues = runSessionCues(
      workout: workout,
      metrics: metrics,
      splits: bundle.splits,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeChips(workout: workout, splits: bundle.splits),
        const SizedBox(height: 10),
        _BasicsGrid(workout: workout),
        if (_hasStimulus(metrics, workout)) ...[
          const SizedBox(height: 14),
          const _SectionKicker('This session'),
          const SizedBox(height: 10),
          _StimulusBlock(workout: workout, metrics: metrics),
        ],
        if (bundle.points.isNotEmpty) ...[
          const SizedBox(height: 14),
          RunSessionCharts(
            points: bundle.points,
            title: 'Session story',
            caption: 'Pace · HR · Cadence',
            showStoryTabs: true,
          ),
        ],
        if (bundle.splits.any((s) => s.hasDistanceOrPace)) ...[
          const SizedBox(height: 14),
          const _SectionKicker('Splits'),
          const SizedBox(height: 10),
          RunPaceSplitsTable(splits: bundle.splits, narrative: true),
        ],
        if (_hasForm(metrics)) ...[
          const SizedBox(height: 14),
          const _SectionKicker('Form · session averages'),
          const SizedBox(height: 10),
          _FormGauges(metrics: metrics),
        ],
        if (_hasTerrain(metrics)) ...[
          const SizedBox(height: 14),
          const _SectionKicker('Terrain'),
          const SizedBox(height: 10),
          _TerrainGrid(metrics: metrics),
        ],
        if (cues.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionKicker('Next run · from this session'),
          const SizedBox(height: 10),
          _CuesList(cues: cues),
        ],
        const SizedBox(height: 14),
        const _SectionKicker('After this session'),
        const SizedBox(height: 10),
        const _AfterSessionCard(),
        if (onExport != null || onAllSessions != null) ...[
          const SizedBox(height: 16),
          if (onExport != null) ...[
            FilledButton(
              onPressed: exportBusy ? null : onExport,
              child: exportBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Export session'),
            ),
            const SizedBox(height: 8),
          ],
          if (onAllSessions != null)
            OutlinedButton(
              onPressed: onAllSessions,
              child: const Text('All run sessions'),
            ),
        ],
      ],
    );
  }

  bool _hasStimulus(RunSessionMetrics m, WorkoutSummary w) =>
      m.aerobicEffect != null ||
      m.anaerobicEffect != null ||
      m.sessionLoad != null ||
      m.recoverySec != null ||
      w.hrMin != null ||
      w.hrMax != null ||
      m.avgHrBpm != null;

  bool _hasForm(RunSessionMetrics m) =>
      m.gctMs != null ||
      m.verticalOscillationCm != null ||
      m.balancePct != null ||
      m.strideCm != null;

  bool _hasTerrain(RunSessionMetrics m) =>
      m.elevGainM != null ||
      m.elevLossM != null ||
      m.steps != null ||
      m.cadenceSpm != null;
}

class _SectionKicker extends StatelessWidget {
  const _SectionKicker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.inkDim,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
    );
  }
}

class _ModeChips extends StatelessWidget {
  const _ModeChips({required this.workout, required this.splits});

  final WorkoutSummary workout;
  final List<RunPaceSplit> splits;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final chips = <({String label, Color? tone})>[];
    if (workout.type == 5) {
      chips.add((label: 'Indoor', tone: null));
    } else if (isOutdoorLandWorkout(workout.type)) {
      chips.add((label: 'Outdoor', tone: colors.up));
    }
    if (detectRunWalkTransition(splits)) {
      chips.add((label: 'Run → walk', tone: colors.amber));
    } else if (workout.type == 1) {
      chips.add((label: 'Walk', tone: null));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: c.tone == null
                    ? colors.line
                    : Color.lerp(colors.line, c.tone!, 0.4)!,
              ),
              color: c.tone == null
                  ? colors.bgElev
                  : Color.lerp(colors.bgElev, c.tone!, 0.1),
            ),
            child: Text(
              c.label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'IBM Plex Mono',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: c.tone ?? colors.inkDim,
                  ),
            ),
          ),
      ],
    );
  }
}

class _BasicsGrid extends StatelessWidget {
  const _BasicsGrid({required this.workout});

  final WorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final cells = <({String label, String value})>[
      if (formatDistanceKm(workout.distanceM) != null)
        (label: 'Distance', value: formatDistanceKm(workout.distanceM)!),
      if (formatDurationHero(workout.durationSec) != null)
        (label: 'Duration', value: formatDurationHero(workout.durationSec)!),
      if (formatAvgPaceSecPerKm(workout.distanceM, workout.durationSec) != null)
        (
          label: 'Avg pace',
          value: formatAvgPaceSecPerKm(
            workout.distanceM,
            workout.durationSec,
          )!,
        ),
      if (workout.calories != null)
        (label: 'Calories', value: '${workout.calories}'),
    ];
    if (cells.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cell in cells)
              SizedBox(
                width: w,
                child: _SignalCell(label: cell.label, value: cell.value),
              ),
          ],
        );
      },
    );
  }
}

class _SignalCell extends StatelessWidget {
  const _SignalCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: Color.lerp(colors.bgElev, colors.accent, 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.inkDim,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'IBM Plex Mono',
              fontWeight: FontWeight.w500,
              color: colors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StimulusBlock extends StatelessWidget {
  const _StimulusBlock({required this.workout, required this.metrics});

  final WorkoutSummary workout;
  final RunSessionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final heroes = <({String label, String value, String hint})>[
      if (metrics.aerobicEffect != null)
        (
          label: 'Aerobic TE',
          value: metrics.aerobicEffect!.toStringAsFixed(1),
          hint: teBandHint(metrics.aerobicEffect!),
        ),
      if (metrics.anaerobicEffect != null)
        (
          label: 'Anaerobic TE',
          value: metrics.anaerobicEffect!.toStringAsFixed(1),
          hint: teBandHint(metrics.anaerobicEffect!, anaerobic: true),
        ),
    ];
    final cells = <({String label, String value})>[
      if (metrics.sessionLoad != null)
        (label: 'Training load', value: '${metrics.sessionLoad}'),
      if (metrics.recoverySec != null)
        (
          label: 'Recovery',
          value: formatRecoveryMinutes(metrics.recoverySec! ~/ 60) ?? '—',
        ),
      if (_hrRange(workout) != null)
        (label: 'Heart rate', value: _hrRange(workout)!),
      if (metrics.avgHrBpm != null)
        (label: 'Avg HR', value: '${metrics.avgHrBpm}'),
    ];

    return Column(
      children: [
        if (heroes.isNotEmpty)
          Row(
            children: [
              for (var i = 0; i < heroes.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                    decoration: BoxDecoration(
                      color: colors.bgElev,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          heroes[i].label.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.inkDim,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          heroes[i].value,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontFamily: 'IBM Plex Mono',
                            fontWeight: FontWeight.w600,
                            color: colors.accent,
                            letterSpacing: -0.5,
                            height: 1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          heroes[i].hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.inkFaint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        if (heroes.isNotEmpty && cells.isNotEmpty) const SizedBox(height: 8),
        if (cells.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final w = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cell in cells)
                    SizedBox(
                      width: w,
                      child: _DerivedCell(
                        label: cell.label,
                        value: cell.value,
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  String? _hrRange(WorkoutSummary w) {
    final min = w.hrMin;
    final max = w.hrMax;
    if (min != null && max != null) return '$min–$max';
    if (min != null) return '$min';
    if (max != null) return '$max';
    return null;
  }
}

class _DerivedCell extends StatelessWidget {
  const _DerivedCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.inkFaint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'IBM Plex Mono',
              fontWeight: FontWeight.w500,
              color: colors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormGauges extends StatelessWidget {
  const _FormGauges({required this.metrics});

  final RunSessionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final gauges = <_GaugeSpec>[
      if (metrics.gctMs != null)
        _GaugeSpec(
          label: 'GCT',
          value: '${metrics.gctMs}',
          unit: 'ms',
          frac: (metrics.gctMs! / 500).clamp(0.08, 1.0),
        ),
      if (metrics.verticalOscillationCm != null)
        _GaugeSpec(
          label: 'Vertical osc.',
          value: metrics.verticalOscillationCm!.toStringAsFixed(1),
          unit: 'cm',
          frac: (metrics.verticalOscillationCm! / 14).clamp(0.08, 1.0),
        ),
      if (metrics.balancePct != null)
        _GaugeSpec(
          label: 'Balance L/R',
          value: metrics.balancePct!.toStringAsFixed(1),
          unit: '%',
          frac: (metrics.balancePct! / 100).clamp(0.0, 1.0),
          balance: true,
          hint: 'Monitor only — not injury risk',
        ),
      if (metrics.strideCm != null)
        _GaugeSpec(
          label: 'Stride',
          value: (metrics.strideCm! / 100).toStringAsFixed(2),
          unit: 'm',
          frac: (metrics.strideCm! / 160).clamp(0.08, 1.0),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in gauges)
              SizedBox(width: w, child: _FormGauge(spec: g)),
          ],
        );
      },
    );
  }
}

class _GaugeSpec {
  const _GaugeSpec({
    required this.label,
    required this.value,
    required this.unit,
    required this.frac,
    this.balance = false,
    this.hint,
  });

  final String label;
  final String value;
  final String unit;
  final double frac;
  final bool balance;
  final String? hint;
}

class _FormGauge extends StatelessWidget {
  const _FormGauge({required this.spec});

  final _GaugeSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.inkFaint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: spec.value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: 'IBM Plex Mono',
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                TextSpan(
                  text: ' ${spec.unit}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'IBM Plex Mono',
                    color: colors.inkFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: spec.balance
                  ? Row(
                      children: [
                        Flexible(
                          flex: math.max(1, (spec.frac * 1000).round()),
                          child: Container(color: colors.accent),
                        ),
                        Flexible(
                          flex: math.max(1, ((1 - spec.frac) * 1000).round()),
                          child: Container(
                            color: Color.lerp(colors.amber, colors.line, 0.3),
                          ),
                        ),
                      ],
                    )
                  : LinearProgressIndicator(
                      value: spec.frac,
                      minHeight: 6,
                      backgroundColor: colors.line,
                      color: colors.accent,
                    ),
            ),
          ),
          if (spec.hint != null) ...[
            const SizedBox(height: 6),
            Text(
              spec.hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.inkFaint,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TerrainGrid extends StatelessWidget {
  const _TerrainGrid({required this.metrics});

  final RunSessionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final cells = <({String label, String value})>[
      if (metrics.elevGainM != null)
        (
          label: 'Elev gain',
          value: '+${metrics.elevGainM!.toStringAsFixed(1)} m',
        ),
      if (metrics.elevLossM != null)
        (
          label: 'Elev loss',
          value: '−${metrics.elevLossM!.toStringAsFixed(1)} m',
        ),
      if (metrics.steps != null) (label: 'Steps', value: '${metrics.steps}'),
      if (metrics.cadenceSpm != null)
        (label: 'Cadence avg', value: '${metrics.cadenceSpm}'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cell in cells)
              SizedBox(
                width: w,
                child: _DerivedCell(label: cell.label, value: cell.value),
              ),
          ],
        );
      },
    );
  }
}

class _CuesList extends StatelessWidget {
  const _CuesList({required this.cues});

  final List<RunSessionCue> cues;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < cues.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: i == 0
                  ? Color.lerp(colors.bgElev, colors.amber, 0.12)
                  : colors.bgElev,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: i == 0
                    ? Color.lerp(colors.line, colors.amber, 0.45)!
                    : colors.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cues[i].tag.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.amber,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cues[i].title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cues[i].body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.inkDim,
                    height: 1.4,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AfterSessionCard extends StatelessWidget {
  const _AfterSessionCard();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ContextRow(
          title: 'Sleep',
          tag: 'Night after',
          value: 'Waiting for data',
        ),
        SizedBox(height: 8),
        _ContextRow(
          title: 'How you felt',
          tag: 'Morning check-in',
          value: 'Not logged',
        ),
      ],
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({
    required this.title,
    required this.tag,
    required this.value,
  });

  final String title;
  final String tag;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tag.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.inkFaint,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'IBM Plex Mono',
              color: colors.inkDim,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}


class RunSessionCue {
  const RunSessionCue({
    required this.tag,
    required this.title,
    required this.body,
  });

  final String tag;
  final String title;
  final String body;
}

/// Honest, omit-null coaching cues from present session fields only.
List<RunSessionCue> runSessionCues({
  required WorkoutSummary workout,
  required RunSessionMetrics metrics,
  required List<RunPaceSplit> splits,
}) {
  final out = <RunSessionCue>[];
  final cad = metrics.cadenceSpm;
  if (cad != null && cad > 0 && cad < 160) {
    final target = math.min(170, cad + 8);
    out.add(
      RunSessionCue(
        tag: 'Cadence cue',
        title: 'Hold ~$target spm on the run segment',
        body:
            'A small cadence bump often lowers loading rate and vertical '
            'oscillation. Cue only while running — not during a walk cool-down.',
      ),
    );
  }
  final aero = metrics.aerobicEffect;
  if (aero != null) {
    final recovery = metrics.recoverySec == null
        ? null
        : formatRecoveryMinutes(metrics.recoverySec! ~/ 60);
    out.add(
      RunSessionCue(
        tag: 'Stimulus',
        title:
            'TE ${aero.toStringAsFixed(1)} = ${teBandHint(aero).toLowerCase()}',
        body: recovery == null
            ? 'Use this TE band to plan tomorrow\'s effort.'
            : 'Recovery clock $recovery. Soft easy until the clock clears; '
                'save hard work for later.',
      ),
    );
  }
  final narrative = annotateRunSplits(splits);
  final runPaces = narrative
      .where((n) => !n.isWalk && n.split.paceSec != null && n.split.paceSec! > 0)
      .map((n) => n.split.paceSec!)
      .toList();
  if (runPaces.length >= 2 && runPaces.last < runPaces.first) {
    out.add(
      const RunSessionCue(
        tag: 'Pacing',
        title: 'Negative split on the run half',
        body:
            'Later run km faster than early — keep that pattern on continuous '
            'runs; don’t read a walk split as fade.',
      ),
    );
  }
  return out;
}
