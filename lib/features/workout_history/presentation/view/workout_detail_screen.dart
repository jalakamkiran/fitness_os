import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/diagnostics/data/run_session_export_envelope.dart';
import 'package:fitness_os/features/diagnostics/data/run_session_export_service.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/data/swim_reasoner_service.dart';
import 'package:fitness_os/features/workout_history/domain/offline_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_invent_guard.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_stroke_label.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:fitness_os/features/workout_history/presentation/view/coach_settings_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_session_sections.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_stroke_icon.dart';

class WorkoutDetailScreen extends StatelessWidget {
  const WorkoutDetailScreen({
    super.key,
    required this.workout,
    this.runSessionStore,
    this.preloadedPaceSplits,
    this.preloadedStreamPoints,
    this.runSessionExportService,
    this.shareSessionExport,
    this.sessionExportOverride,
    this.sessionExportBusyOverride,
  });

  final WorkoutSummary workout;

  /// Optional override for Run side-file loaders (tests). Production uses DI.
  final RunSessionStore? runSessionStore;

  /// Test seam: inject pace splits without side-file IO.
  final List<RunPaceSplit>? preloadedPaceSplits;

  /// Test seam: inject chart points without side-file IO.
  final List<RunStreamPoint>? preloadedStreamPoints;

  /// Test seam — production uses GetIt [RunSessionExportService].
  final RunSessionExportService? runSessionExportService;

  /// Test seam — production uses [SharePlus].
  final Future<void> Function(File file)? shareSessionExport;

  /// Test seam — when set, used instead of [RunSessionExportService.exportSessionToCache].
  final Future<RunSessionExportResult> Function()? sessionExportOverride;

  /// Test seam — when set, used instead of [RunSessionExportService.isBusy].
  final bool Function()? sessionExportBusyOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRun = isRunWorkout(workout.type);
    final isOutdoor = isOutdoorRunWorkout(workout.type);
    final swim = isRun ? null : CanonicalSwimSession.fromWorkoutSummary(workout);
    final analytics = swim == null ? null : analyzeSwimSession(swim.p0);
    final runMetrics =
        isRun ? RunSessionMetrics.fromSummary(workout) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_typeLabel(workout.type)} #${workout.number}'),
        actions: [
          if (isOutdoor)
            _OutdoorRunExportAction(
              workout: workout,
              exportService: runSessionExportService,
              shareExport: shareSessionExport,
              exportOverride: sessionExportOverride,
              exportBusyOverride: sessionExportBusyOverride,
            ),
          IconButton(
            tooltip: 'Reasoner settings',
            icon: const Icon(Icons.psychology_outlined),
            onPressed: () => CoachSettingsRoute.go(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _CountHintsCard(workout: workout),
          const SizedBox(height: 16),
          // IA (1): session header.
          _SectionCard(
            title: 'Session',
            children: [
              _Row('Start', _formatWhen(workout.startTime)),
              _Row('End', _formatWhen(workout.endTime)),
              _Row('Duration', _formatDuration(workout.durationSec)),
              _Row('Type', '${workout.type} (${_typeLabel(workout.type)})'),
              if (workout.calories != null)
                _Row('Calories', '${workout.calories} kcal'),
              if (workout.distanceM != null)
                _Row('Distance', '${workout.distanceM} m'),
              // Steps live under Form on the Run path (IA 4).
              if (!isRun && workout.steps != null)
                _Row('Steps', '${workout.steps}'),
            ],
          ),
          if (isRun && runMetrics != null) ...[
            // IA (2): this-run recovery / stress / load — omit if undecoded.
            if (runMetrics.hasThisRunTraining) ...[
              const SizedBox(height: 12),
              RunThisRunTrainingCard(metrics: runMetrics),
            ],
            // IA (3): native zones only — never invent minutes.
            if (runMetrics.hasNativeZones) ...[
              const SizedBox(height: 12),
              RunNativeZonesCard(metrics: runMetrics),
            ],
            // IA (4): form tiles when present.
            if (runMetrics.hasFormTiles) ...[
              const SizedBox(height: 12),
              RunFormTilesCard(metrics: runMetrics),
            ],
            // Scalar HR peaks (fetched Totals) — before stream charts.
            if (_hasHr(workout)) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Heart rate',
                children: [
                  if (workout.hrMin != null)
                    _Row('Min', '${workout.hrMin} bpm'),
                  if (workout.hrMax != null)
                    _Row('Max', '${workout.hrMax} bpm'),
                  if (workout.hrPeak != null)
                    _Row('Peak', '${workout.hrPeak} bpm'),
                ],
              ),
            ],
            // IA (5–6): splits then pace/HR charts — gated on side-files.
            const SizedBox(height: 12),
            RunSessionStreamsSection(
              workoutNumber: workout.number,
              store: runSessionStore,
              preloadedSplits: preloadedPaceSplits,
              preloadedPoints: preloadedStreamPoints,
            ),
          ] else ...[
            if (_hasHr(workout)) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Heart rate',
                children: [
                  if (workout.hrMin != null)
                    _Row('Min', '${workout.hrMin} bpm'),
                  if (workout.hrMax != null)
                    _Row('Max', '${workout.hrMax} bpm'),
                  if (workout.hrPeak != null)
                    _Row('Peak', '${workout.hrPeak} bpm'),
                ],
              ),
            ],
            if (_hasSwim(workout)) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Swim',
                children: [
                  if (workout.swimType != null)
                    _Row('Swim type', swimStrokeLabel(workout.swimType!)),
                  if (workout.strokes != null)
                    _Row('Strokes', '${workout.strokes}'),
                  if (workout.strokeRate != null)
                    _Row('Stroke rate', '${workout.strokeRate} /min'),
                  if (workout.avgSwolf != null)
                    _Row('Avg SWOLF', '${workout.avgSwolf}'),
                  if (workout.poolLength != null)
                    _Row('Pool length', _formatPoolLength(workout.poolLength!)),
                  if (workout.laps != null) _Row('Laps', '${workout.laps}'),
                ],
              ),
            ],
            if (swim != null) ...[
              const SizedBox(height: 12),
              _P0MetricsCard(session: swim),
              if (analytics != null) ...[
                const SizedBox(height: 12),
                _SessionAnalyticsCard(analytics: analytics),
              ],
              const SizedBox(height: 12),
              _DiagnosesLoader(workoutNumber: workout.number),
              const SizedBox(height: 12),
              _CoachRecsLoader(workoutNumber: workout.number),
            ],
            if (swim != null && swim.p0.laps.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SwimChartsAndIntervals(
                laps: swim.p0.laps,
                poolLengthM: swim.poolLengthM,
                hrCoverage: swim.p0.hrCoverage,
              ),
            ] else if (workout.segments != null &&
                workout.segments!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _LapTable(segments: workout.segments!),
            ],
            if (workout.sampleCount != null && workout.sampleCount! > 0) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Samples',
                children: [
                  _Row('Sample count', '${workout.sampleCount}'),
                ],
              ),
            ],
            if (workout.enrichmentTags != null &&
                workout.enrichmentTags!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Enrichment tags',
                subtitle: '${workout.enrichmentTags!.length} tag(s) on wire',
                children: [
                  for (final tag in workout.enrichmentTags!)
                    _Row('Tag ${tag.id}', 'len ${tag.len}'),
                ],
              ),
            ],
            if (!_hasEnrichment(workout)) ...[
              const SizedBox(height: 12),
              BpContainer(
                padding: EdgeInsets.zero,
                child: Text(
                  'No enrichment counts or tags on this workout yet — '
                  'sync again after a watch session with data/pace/segments.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Outdoor Run AppBar overflow: Export for AI (confirm → assemble → share).
class _OutdoorRunExportAction extends StatefulWidget {
  const _OutdoorRunExportAction({
    required this.workout,
    this.exportService,
    this.shareExport,
    this.exportOverride,
    this.exportBusyOverride,
  });

  final WorkoutSummary workout;
  final RunSessionExportService? exportService;
  final Future<void> Function(File file)? shareExport;
  final Future<RunSessionExportResult> Function()? exportOverride;
  final bool Function()? exportBusyOverride;

  @override
  State<_OutdoorRunExportAction> createState() =>
      _OutdoorRunExportActionState();
}

class _OutdoorRunExportActionState extends State<_OutdoorRunExportAction> {
  bool _assembling = false;

  RunSessionExportService get _export =>
      widget.exportService ?? sl<RunSessionExportService>();

  bool get _serviceBusy {
    if (widget.exportBusyOverride != null) {
      return widget.exportBusyOverride!();
    }
    // Test seam: when exportOverride is supplied, skip GetIt busy probe.
    if (widget.exportOverride != null) {
      return false;
    }
    return _export.isBusy;
  }

  Future<RunSessionExportResult> _runExport() {
    if (widget.exportOverride != null) {
      return widget.exportOverride!();
    }
    return _export.exportSessionToCache(widget.workout);
  }

  Future<void> _onExportForAi() async {
    if (_assembling) return;

    if (_serviceBusy) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Export blocked — wait for sync, Forget, or another export to finish.',
          ),
        ),
      );
      return;
    }

    final identity =
        RunSessionExportService.confirmIdentityLines(widget.workout);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export for AI?'),
        content: Text(
          '$identity\n\n'
          'This creates a JSON dump of this Outdoor Run session. It contains '
          'non-anonymized health biometrics (heart rate, form metrics, and '
          'opaque leftover payloads). Structured GPS/location series are '
          'omitted, but undecoded leftover bytes may still include '
          'location-related wire data until those tags are catalogued. After '
          'you share it, recipients may keep copies — Forget Device does not '
          'revoke shared copies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _assembling = true);

    final result = await _runExport();
    if (!mounted) return;

    if (!result.isSuccess || result.file == null) {
      setState(() => _assembling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Export failed.')),
      );
      return;
    }

    final file = result.file!;
    final sharePath = file.absolute.path;
    if (!sharePath.contains(
      '/${RunSessionExportEnvelope.exportCacheDirName}/',
    )) {
      setState(() => _assembling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export path refused — not under export cache.'),
        ),
      );
      return;
    }

    try {
      final share = widget.shareExport;
      if (share != null) {
        await share(file);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: 'Fathom Outdoor Run session export',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _assembling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _assembling = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Export for AI',
      icon: const Icon(Icons.ios_share),
      onPressed: _assembling ? null : _onExportForAi,
    );
  }
}

class _CoachRecsLoader extends StatelessWidget {
  const _CoachRecsLoader({required this.workoutNumber});

  final int workoutNumber;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SwimDiagnosisReport>(
      future: sl<WorkoutHistoryRepository>().loadSwimDiagnosisReport(
        focusWorkoutNumber: workoutNumber,
      ),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || snap.data == null) {
          return const _SectionCard(
            title: 'Recommendations',
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Loading recommendations…'),
              ),
            ],
          );
        }
        return _CoachRecsCard(
          workoutNumber: workoutNumber,
          report: snap.data!,
        );
      },
    );
  }
}

class _CoachRecsCard extends StatefulWidget {
  const _CoachRecsCard({
    required this.workoutNumber,
    required this.report,
  });

  final int workoutNumber;
  final SwimDiagnosisReport report;

  @override
  State<_CoachRecsCard> createState() => _CoachRecsCardState();
}

class _CoachRecsCardState extends State<_CoachRecsCard> {
  bool _loadingCoach = false;
  SwimReasonerResult? _coach;
  late List<SwimRecommendation> _recs;

  @override
  void initState() {
    super.initState();
    _recs = recommendationsForReport(widget.report);
  }

  Future<void> _runReasoner() async {
    setState(() {
      _loadingCoach = true;
      _coach = null;
    });
    final result = await sl<SwimReasonerService>().reason(
      report: widget.report,
      recommendations: _recs,
      workoutNumber: widget.workoutNumber,
    );
    if (!mounted) return;
    setState(() {
      _loadingCoach = false;
      _coach = result;
      if (result.ok && result.orderedRecIds.isNotEmpty) {
        final byId = {for (final r in _recs) r.id: r};
        _recs = [
          for (final id in result.orderedRecIds)
            if (byId[id] != null) byId[id]!,
          for (final r in _recs)
            if (!result.orderedRecIds.contains(r.id)) r,
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Recommendations + reasoner',
      subtitle: 'Allow-listed actions · Qwen3 / offline ranking',
      children: [
        if (_recs.isEmpty)
          const _Row('Recs', 'None mapped for this session')
        else
          for (final r in _recs) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'via ${r.sourceDiagnosisIds.join(', ')} · '
                    'metrics: ${r.metricIds.join(', ')}'
                    '${r.bibleHint != null ? ' · ${r.bibleHint}' : ''}'
                    '${_coach?.rationaleByRecId[r.id] != null ? ' · ${_coach!.rationaleByRecId[r.id]}' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        const SizedBox(height: 4),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: _loadingCoach ? null : _runReasoner,
              icon: _loadingCoach
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.psychology_outlined, size: 18),
              label: const Text('Run reasoner'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => CoachSettingsRoute.go(context),
              child: const Text('Qwen3 settings'),
            ),
          ],
        ),
        if (_coach != null) ...[
          const SizedBox(height: 12),
          if (!_coach!.ok)
            Text(
              _coach!.error ?? 'Reasoner failed',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else ...[
            Text(
              'Reasoning (${_coach!.source})',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _coach!.summary?.isNotEmpty == true
                  ? _coach!.summary!
                  : 'No summary returned.',
              style: theme.textTheme.bodySmall,
            ),
            if (_coach!.notes != null && _coach!.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _coach!.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }
}

class _DiagnosesLoader extends StatelessWidget {
  const _DiagnosesLoader({required this.workoutNumber});

  final int workoutNumber;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SwimDiagnosisReport>(
      future: sl<WorkoutHistoryRepository>().loadSwimDiagnosisReport(
        focusWorkoutNumber: workoutNumber,
      ),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SectionCard(
            title: 'Diagnoses',
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Loading diagnoses…'),
              ),
            ],
          );
        }
        final report = snap.data;
        if (report == null) {
          return const SizedBox.shrink();
        }
        return _DiagnosesCard(report: report);
      },
    );
  }
}

class _DiagnosesCard extends StatelessWidget {
  const _DiagnosesCard({required this.report});

  final SwimDiagnosisReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trends = report.trends;
    return _SectionCard(
      title: 'Diagnoses',
      subtitle: 'Evidence → Diagnosis (deterministic)',
      children: [
        if (trends.sessionCount > 0) ...[
          _Row('Swim sessions', '${trends.sessionCount}'),
          if (trends.totalDistanceM != null)
            _Row('Total volume', '${trends.totalDistanceM} m'),
          if (trends.totalMovingSec != null)
            _Row('Moving time', _formatDuration(trends.totalMovingSec!)),
          if (trends.paceDeltaPct != null)
            _Row(
              'Pace trend',
              '${trends.paceDeltaPct! >= 0 ? '+' : ''}'
              '${trends.paceDeltaPct!.toStringAsFixed(0)}% latest vs first',
            ),
          if (trends.swolfDelta != null)
            _Row(
              'SWOLF trend',
              '${trends.swolfDelta! >= 0 ? '+' : ''}${trends.swolfDelta}',
            ),
          const SizedBox(height: 6),
        ],
        Text(
          'This session',
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        for (final d in report.sessionDiagnoses) _DiagnosisTile(diagnosis: d),
        if (report.trendDiagnoses.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Across sessions',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final d in report.trendDiagnoses) _DiagnosisTile(diagnosis: d),
        ],
      ],
    );
  }
}

class _DiagnosisTile extends StatelessWidget {
  const _DiagnosisTile({required this.diagnosis});

  final SwimDiagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  diagnosis.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _ConfidenceChip(confidence: diagnosis.confidence),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            diagnosis.summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'metrics: ${diagnosis.metricIds.join(', ')}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionAnalyticsCard extends StatelessWidget {
  const _SessionAnalyticsCard({required this.analytics});

  final SwimSessionAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Session analytics',
      subtitle: 'Interval-based (not proven lengths)',
      children: [
        if (analytics.paceDecayPct != null)
          _Row(
            'Pace decay',
            '${analytics.paceDecayPct! >= 0 ? '+' : ''}'
            '${analytics.paceDecayPct!.toStringAsFixed(0)}% 2nd vs 1st half',
          ),
        if (analytics.paceCvPct != null)
          _Row('Pace CV', '${analytics.paceCvPct!.toStringAsFixed(0)}%'),
        if (analytics.swolfDelta != null)
          _Row(
            'SWOLF Δ',
            '${analytics.swolfDelta! >= 0 ? '+' : ''}${analytics.swolfDelta}',
          ),
        const SizedBox(height: 4),
        for (final claim in analytics.claims) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        claim.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _ConfidenceChip(confidence: claim.confidence),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  claim.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (analytics.intervalEfficiencies.any((e) => e.swolf != null)) ...[
          const SizedBox(height: 4),
          Text(
            'Interval SWOLF',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final e in analytics.intervalEfficiencies)
            if (e.swolf != null)
              _Row(
                '#${e.index + 1}',
                e.strokesPer25m != null
                    ? 'SWOLF ${e.swolf} · ${e.strokesPer25m!.toStringAsFixed(1)} str/25m'
                    : 'SWOLF ${e.swolf}',
              ),
        ],
        if (!analytics.showHrPhysiology)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'HR zones/drift hidden — no in-workout sample stream.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});

  final SwimConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, fg, bg) = switch (confidence) {
      SwimConfidence.high => ('High', scheme.onPrimaryContainer, scheme.primaryContainer),
      SwimConfidence.med => ('Med', scheme.onSecondaryContainer, scheme.secondaryContainer),
      SwimConfidence.low => ('Low', scheme.onErrorContainer, scheme.errorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _P0MetricsCard extends StatelessWidget {
  const _P0MetricsCard({required this.session});

  final CanonicalSwimSession session;

  @override
  Widget build(BuildContext context) {
    final p0 = session.p0;
    return _SectionCard(
      title: 'P0 metrics',
      subtitle: _p0Subtitle(p0),
      children: [
        _Row('HR coverage', p0.hrCoverage.name),
        if (p0.avgPaceSecPer100m != null)
          _Row('Avg pace', _paceCell(p0.avgPaceSecPer100m)),
        if (p0.movingAvgPaceSecPer100m != null)
          _Row('Moving pace', _paceCell(p0.movingAvgPaceSecPer100m)),
        if (p0.totalStrokes != null) _Row('Strokes', '${p0.totalStrokes}'),
        if (p0.avgSwolf != null) _Row('Avg SWOLF', '${p0.avgSwolf}'),
        if (p0.strokeRatePerMin != null)
          _Row('Stroke rate', '${p0.strokeRatePerMin} /min'),
        if (p0.lapCount != null)
          _Row(
            'Parsed laps',
            p0.reportedLaps != null
                ? '${p0.lapCount} / ${p0.reportedLaps} reported'
                : '${p0.lapCount}',
          ),
        if (session.poolLengthM != null)
          _Row('Pool length', '${session.poolLengthM} m'),
        if (p0.lengthCoveragePartial)
          const _Row(
            'Coverage',
            'PARTIAL — fewer segment rows than watch laps',
          ),
      ],
    );
  }

  String _p0Subtitle(SwimP0Metrics p0) {
    if (p0.lengthCoveragePartial) return 'Length coverage PARTIAL';
    if (p0.hrCoverage == SwimHrCoverage.partial) {
      return 'In-workout HR PARTIAL (totals only)';
    }
    if (p0.hrCoverage == SwimHrCoverage.absent) return 'No in-workout HR';
    return 'Computed from Totals + segments';
  }

  String _paceCell(int? secPer100m) {
    if (secPer100m == null) return '—';
    final m = secPer100m ~/ 60;
    final s = secPer100m % 60;
    return '$m:${s.toString().padLeft(2, '0')} /100m';
  }
}

class _CountHintsCard extends StatelessWidget {
  const _CountHintsCard({required this.workout});

  final WorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enrichment counts',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CountChip(
                    label: 'data',
                    value: workout.dataCount,
                    fetched: _dataFetchedStatus(workout),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountChip(
                    label: 'pace',
                    value: workout.paceCount,
                    fetched: _paceFetchedStatus(workout),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountChip(
                    label: 'segments',
                    value: workout.segmentsCount,
                    fetched: _segmentsFetchedStatus(workout),
                  ),
                ),
              ],
            ),
            if (workout.enrichmentStatus != null) ...[
              const SizedBox(height: 8),
              Text(
                'Sync: ${workout.enrichmentStatus}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.value,
    this.fetched,
  });

  final String label;
  final int? value;
  final bool? fetched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasHint = value != null && value! > 0;
    final ok = fetched == true;
    final fail = hasHint && fetched == false;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: ok
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : fail
                ? scheme.errorContainer.withValues(alpha: 0.25)
                : hasHint
                    ? scheme.primary.withValues(alpha: 0.08)
                    : scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ok
              ? scheme.primary
              : fail
                  ? scheme.error
                  : hasHint
                      ? scheme.primary
                      : scheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (fetched != null) ...[
                Text(
                  ok ? '✓' : '✗',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ok ? scheme.primary : scheme.error,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                value?.toString() ?? '—',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: hasHint ? scheme.primary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Charts + interval table share one invent-guard filter (default: hide garbage).
class _SwimChartsAndIntervals extends StatefulWidget {
  const _SwimChartsAndIntervals({
    required this.laps,
    required this.hrCoverage,
    this.poolLengthM,
  });

  final List<SwimLapMetrics> laps;
  final int? poolLengthM;
  final SwimHrCoverage hrCoverage;

  @override
  State<_SwimChartsAndIntervals> createState() =>
      _SwimChartsAndIntervalsState();
}

class _SwimChartsAndIntervalsState extends State<_SwimChartsAndIntervals> {
  /// Product lock: invent-guard on by default (filtered laps hidden).
  bool _includeFiltered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filteredCount = countInventGuardFilteredLaps(
      widget.laps,
      poolLengthM: widget.poolLengthM,
    );
    final active = filterSwimLapsForAnalytics(
      widget.laps,
      poolLengthM: widget.poolLengthM,
      includeFiltered: _includeFiltered,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (filteredCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              child: CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                value: _includeFiltered,
                onChanged: (v) => setState(() => _includeFiltered = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Include filtered laps',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _includeFiltered
                      ? 'Showing $filteredCount filtered laps — charts/table use the same set'
                      : '$filteredCount hidden by invent-guard · charts/table synced',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        SwimSessionCharts(
          laps: active,
          hrCoverage: widget.hrCoverage,
        ),
        if (active.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SwimLapMetricsTable(
            laps: active,
            includeFiltered: _includeFiltered,
            filteredCount: filteredCount,
          ),
        ],
      ],
    );
  }
}

class _SwimLapMetricsTable extends StatelessWidget {
  const _SwimLapMetricsTable({
    required this.laps,
    required this.includeFiltered,
    required this.filteredCount,
  });

  final List<SwimLapMetrics> laps;
  final bool includeFiltered;
  final int filteredCount;

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Intervals',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Same lap set as charts',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 48,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Dev')),
                  DataColumn(label: Text('Dist')),
                  DataColumn(label: Text('Time')),
                  DataColumn(label: Text('Strokes')),
                  DataColumn(label: Text('SWOLF')),
                  DataColumn(label: Text('Pace')),
                ],
                rows: [
                  for (var i = 0; i < laps.length; i++)
                    DataRow(
                      cells: [
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SwimStrokeIcon(style: laps[i].style),
                              const SizedBox(width: 6),
                              Text('I${i + 1}'),
                            ],
                          ),
                        ),
                        DataCell(Text('${laps[i].index + 1}')),
                        DataCell(Text(_cell(laps[i].distanceM, suffix: 'm'))),
                        DataCell(
                          Text(_formatDuration(laps[i].durationSec ?? 0)),
                        ),
                        DataCell(Text(_cell(laps[i].strokes))),
                        DataCell(Text(_cell(laps[i].swolf))),
                        DataCell(Text(_paceCell(laps[i].paceSecPer100m))),
                      ],
                    ),
                ],
              ),
            ),
            if (filteredCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                includeFiltered
                    ? 'Showing $filteredCount filtered laps — charts/table use the same set.'
                    : 'Invent-guard hiding $filteredCount garbage laps from charts and table. P0 card still uses full parsed set.',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _cell(int? v, {String suffix = ''}) =>
      v == null ? '—' : '$v$suffix';

  String _paceCell(int? secPer100m) =>
      secPer100m == null ? '—' : '${secPer100m}s/100m';
}

class _LapTable extends StatelessWidget {
  const _LapTable({required this.segments});

  final List<WorkoutSegment> segments;

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Intervals',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Parsed swim segments (not proven lengths)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 48,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Dist')),
                  DataColumn(label: Text('Time')),
                  DataColumn(label: Text('Strokes')),
                  DataColumn(label: Text('SWOLF')),
                  DataColumn(label: Text('Pace')),
                ],
                rows: [
                  for (final seg in segments)
                    DataRow(
                      cells: [
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SwimStrokeIcon(
                                style: seg.style ?? seg.swimType,
                              ),
                              const SizedBox(width: 6),
                              Text('${seg.index + 1}'),
                            ],
                          ),
                        ),
                        DataCell(Text(_cell(seg.distanceM, suffix: 'm'))),
                        DataCell(Text(_formatDuration(seg.durationSec ?? 0))),
                        DataCell(Text(_cell(seg.strokes))),
                        DataCell(Text(_cell(seg.avgSwolf))),
                        DataCell(Text(_paceCell(seg.paceSecPer100m))),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _cell(int? v, {String suffix = ''}) =>
      v == null ? '—' : '$v$suffix';

  String _paceCell(int? secPer100m) =>
      secPer100m == null ? '—' : '${secPer100m}s/100m';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

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

bool _hasHr(WorkoutSummary w) =>
    w.hrMin != null || w.hrMax != null || w.hrPeak != null;

bool _hasSwim(WorkoutSummary w) =>
    w.swimType != null ||
    w.strokes != null ||
    w.strokeRate != null ||
    w.avgSwolf != null ||
    w.poolLength != null ||
    w.laps != null;

bool _hasEnrichment(WorkoutSummary w) =>
    _dataFetchedStatus(w) == true ||
    _paceFetchedStatus(w) == true ||
    _segmentsFetchedStatus(w) == true ||
    (w.enrichmentTags != null && w.enrichmentTags!.isNotEmpty);

bool? _dataFetchedStatus(WorkoutSummary w) {
  if (w.dataCount == null || w.dataCount! <= 0) return null;
  return w.sampleCount != null && w.sampleCount! > 0;
}

bool? _paceFetchedStatus(WorkoutSummary w) {
  if (w.paceCount == null || w.paceCount! <= 0) return null;
  return w.enrichmentStatus == 'ok';
}

bool? _segmentsFetchedStatus(WorkoutSummary w) {
  if (w.segmentsCount == null || w.segmentsCount! <= 0) return null;
  return w.segments != null && w.segments!.isNotEmpty;
}

String _typeLabel(int type) {
  // Frozen from owner 25m pool probe (2026-07-23): Totals 0x14 type=6 +
  // poolLength cm + laps aligns with Gadgetbridge (pool=6, open water=8).
  const names = <int, String>{
    1: 'Walk',
    2: 'Run',
    3: 'Cycle',
    4: 'Climb',
    5: 'Indoor run',
    6: 'Pool swim',
    7: 'Indoor cycle',
    8: 'Open water',
    9: 'Elliptical',
    10: 'Rower',
    140: 'Strength',
  };
  return names[type] ?? 'Workout type $type';
}

/// Totals tag 0x18 is pool length in centimetres (catalog + 2500→25m probe).
String _formatPoolLength(int cm) {
  if (cm >= 100 && cm % 100 == 0) {
    return '${cm ~/ 100} m';
  }
  if (cm >= 100) {
    final m = cm / 100.0;
    return '${m.toStringAsFixed(m.truncateToDouble() == m ? 0 : 1)} m';
  }
  // Already metres (legacy / mis-scaled) — show as-is.
  return '$cm m';
}

String _formatWhen(int unixSec) {
  if (unixSec <= 0) return 'unknown time';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

String _formatDuration(int sec) {
  if (sec <= 0) return '—';
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
