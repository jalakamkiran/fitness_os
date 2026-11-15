import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/diagnostics/data/run_session_export_envelope.dart';
import 'package:fitness_os/features/diagnostics/data/run_session_export_service.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/data/strength_session_export_service.dart';
import 'package:fitness_os/features/workout_history/data/swim_session_export_service.dart';
import 'package:fitness_os/features/workout_history/data/workout_tcx_export_service.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_insight.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:fitness_os/features/workout_history/presentation/view/coach_settings_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/racket_session_analytics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_session_analytics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/strava_mark_icon.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/strength_session_analytics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_coaching_fold.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_stroke_icon.dart';

class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({
    super.key,
    required this.workout,
    this.runSessionStore,
    this.preloadedPaceSplits,
    this.preloadedStreamPoints,
    this.preloadedLeftovers,
    this.runSessionExportService,
    this.shareSessionExport,
    this.sessionExportOverride,
    this.sessionExportBusyOverride,
    this.exportService,
    this.exportOverride,
    this.exportBusyOverride,
    this.shareExport,
    this.swimExportService,
    this.swimExportOverride,
    this.swimExportBusyOverride,
    this.shareSwimExport,
    this.historyOverride,
    this.tcxExportService,
    this.shareTcx,
    this.digDeeperOverride,
    this.swimInsightOverride,
    this.swimLapsOverride,
  });

  final WorkoutSummary workout;

  /// Optional override for Run side-file loaders (tests). Production uses DI.
  final RunSessionStore? runSessionStore;

  /// Test seam: inject pace splits without side-file IO.
  final List<RunPaceSplit>? preloadedPaceSplits;

  /// Test seam: inject chart points without side-file IO.
  final List<RunStreamPoint>? preloadedStreamPoints;

  /// Test seam: inject Totals leftovers without side-file IO.
  final List<LeftoverTlvBody>? preloadedLeftovers;

  /// Test seam — production uses GetIt [RunSessionExportService].
  final RunSessionExportService? runSessionExportService;

  /// Test seam — production uses [SharePlus] for run exports.
  final Future<void> Function(File file)? shareSessionExport;

  /// Test seam — when set, used instead of [RunSessionExportService.exportSessionToCache].
  final Future<RunSessionExportResult> Function()? sessionExportOverride;

  /// Test seam — when set, used instead of [RunSessionExportService.isBusy].
  final bool Function()? sessionExportBusyOverride;

  /// Test / DI seam — production uses [StrengthSessionExportService] from GetIt.
  final StrengthSessionExportService? exportService;

  /// Test seam — when set, used instead of [StrengthSessionExportService.exportSessionToCache].
  final Future<StrengthSessionExportResult> Function(int workoutNumber)?
      exportOverride;

  /// Test seam — when set, used instead of [StrengthSessionExportService.isBusy].
  final bool Function()? exportBusyOverride;

  /// Test seam — production uses [SharePlus] with `application/json` for strength.
  final Future<void> Function(File file)? shareExport;

  /// Test / DI seam — production uses [SwimSessionExportService] from GetIt.
  final SwimSessionExportService? swimExportService;

  /// Test seam — when set, used instead of [SwimSessionExportService.exportSessionToCache].
  final Future<SwimSessionExportResult> Function(int workoutNumber)?
      swimExportOverride;

  /// Test seam — when set, used instead of [SwimSessionExportService.isBusy].
  final bool Function()? swimExportBusyOverride;

  /// Test seam — production uses [SharePlus] with `application/json` for swim.
  final Future<void> Function(File file)? shareSwimExport;

  /// Test seam — recent-load bars without GetIt repository.
  final List<WorkoutSummary>? historyOverride;

  /// Test seam — production uses [WorkoutTcxExportService] from DI.
  final WorkoutTcxExportService? tcxExportService;

  /// Test seam — production uses [SharePlus] with TCX mime type.
  final Future<void> Function(File file)? shareTcx;

  /// Test seam — swim dig-deeper flag (skips SharedPreferences when set).
  final bool? digDeeperOverride;

  /// Test seam — inject ready insight for swim coach fold.
  final SwimSessionInsight? swimInsightOverride;

  /// Test seam — invent-guarded laps paired with [swimInsightOverride].
  final List<SwimLapMetrics>? swimLapsOverride;

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  bool _exportBusy = false;
  String? _exportStatus;
  bool _sessionRemoved = false;

  WorkoutSummary get workout => widget.workout;

  bool get _isStrength => isStrengthWorkout(workout.type);
  bool get _isSwim => isSwimWorkout(workout.type);
  bool get _isRacket => isRacketSport(workout.type);
  bool get _supportsJsonExport => _isStrength || _isSwim;

  StrengthSessionExportService get _strengthExport =>
      widget.exportService ?? sl<StrengthSessionExportService>();

  SwimSessionExportService get _swimExport =>
      widget.swimExportService ?? sl<SwimSessionExportService>();

  bool get _serviceBusy {
    if (_isSwim) {
      return widget.swimExportBusyOverride?.call() ?? _swimExport.isBusy;
    }
    return widget.exportBusyOverride?.call() ?? _strengthExport.isBusy;
  }

  Future<({bool isSuccess, File? file, int? byteLength, String? message})>
      _runJsonExport(int number) async {
    if (_isSwim) {
      final result = await (widget.swimExportOverride?.call(number) ??
          _swimExport.exportSessionToCache(number));
      return (
        isSuccess: result.isSuccess,
        file: result.file,
        byteLength: result.byteLength,
        message: result.message,
      );
    }
    final result = await (widget.exportOverride?.call(number) ??
        _strengthExport.exportSessionToCache(number));
    return (
      isSuccess: result.isSuccess,
      file: result.file,
      byteLength: result.byteLength,
      message: result.message,
    );
  }

  String get _jsonExportSportLabel => _isSwim ? 'swim' : 'strength';

  String get _jsonExportCacheDir => _isSwim
      ? SwimSessionExportService.exportCacheDirName
      : StrengthSessionExportService.exportCacheDirName;

  int get _jsonExportSoftWarnBytes => _isSwim
      ? SwimSessionExportService.softWarnBytes
      : StrengthSessionExportService.softWarnBytes;

  Future<void> _onExportThisSession() async {
    if (_sessionRemoved || _exportBusy || !_supportsJsonExport) return;
    if (_serviceBusy) {
      setState(() {
        _exportStatus =
            'Export blocked — wait for sync or Forget to finish, then try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_exportStatus!)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export this session?'),
        content: Text(
          'This creates a JSON file of this $_jsonExportSportLabel session, '
          'including session totals and heart-rate samples when available. '
          'It contains non-anonymized health data. '
          'After you share it, recipients may keep copies — deleting the '
          'export cache does not revoke shared copies.',
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

    setState(() {
      _exportBusy = true;
      _exportStatus = 'Assembling export…';
    });

    final result = await _runJsonExport(workout.number);
    if (!mounted) return;

    if (!result.isSuccess || result.file == null) {
      final gone = (result.message ?? '')
          .toLowerCase()
          .contains('no longer on this device');
      setState(() {
        _exportBusy = false;
        _exportStatus = result.message ?? 'Export failed.';
        if (gone) _sessionRemoved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_exportStatus!)),
      );
      return;
    }

    final file = result.file!;
    final bytes = result.byteLength ?? await file.length();
    if (!mounted) return;

    if (bytes > _jsonExportSoftWarnBytes) {
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Large export'),
          content: Text(
            'Export is about $mb MB. Continue to the share sheet?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (cont != true) {
        if (!mounted) return;
        setState(() {
          _exportBusy = false;
          _exportStatus = 'Export saved locally. Share cancelled.';
        });
        return;
      }
    }

    if (!mounted) return;
    final sharePath = file.absolute.path;
    if (!sharePath.contains('/$_jsonExportCacheDir/')) {
      setState(() {
        _exportBusy = false;
        _exportStatus = 'Export path refused — not under export cache.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_exportStatus!)),
      );
      return;
    }

    try {
      final share = _isSwim ? widget.shareSwimExport : widget.shareExport;
      if (share != null) {
        await share(file);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: 'Fathom $_jsonExportSportLabel session export',
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _exportBusy = false;
        _exportStatus = 'Export ready.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exportBusy = false;
        _exportStatus = 'Share failed: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_exportStatus!)),
      );
    }
  }

  bool get _digDeeper {
    if (widget.digDeeperOverride != null) return widget.digDeeperOverride!;
    try {
      return sl<SharedPreferences>().getBool(GateAPrefs.swimDigDeeper) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRun = isRunWorkout(workout.type);
    final isStrength = _isStrength;
    final isSwim = _isSwim;
    final digDeeper = _digDeeper;
    final swim = (!isRun && !isStrength)
        ? CanonicalSwimSession.fromWorkoutSummary(workout)
        : null;
    final analytics = swim == null ? null : analyzeSwimSession(swim.p0);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${workoutTypeLabel(workout.type)} #${workout.number}',
        ),
        actions: [
          if (!_sessionRemoved)
            _ShareTcxAction(
              workout: workout,
              exportService: widget.tcxExportService,
              shareTcx: widget.shareTcx,
            ),
          if (isRun)
            _RunSessionExportAction(
              workout: workout,
              exportService: widget.runSessionExportService,
              shareExport: widget.shareSessionExport,
              exportOverride: widget.sessionExportOverride,
              exportBusyOverride: widget.sessionExportBusyOverride,
            ),
          if (isStrength || isSwim)
            IconButton(
              tooltip: 'Export this session',
              icon: _exportBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              onPressed: (_exportBusy || _sessionRemoved)
                  ? null
                  : _onExportThisSession,
            ),
          // Reasoner settings: residual non-swim/non-run/non-strength only.
          // Swim athlete path uses Advanced tools (Home), not psychology AppBar.
          if (!isStrength && !isRun && !isSwim)
            IconButton(
              tooltip: 'Reasoner settings',
              icon: const Icon(Icons.psychology_outlined),
              onPressed: () => CoachSettingsRoute.go(context),
            ),
        ],
      ),
      body: _sessionRemoved
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Session removed',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (isStrength) ...[
                  StrengthSessionAnalytics(
                    workout: workout,
                    historyOverride: widget.historyOverride,
                    runSessionStore: widget.runSessionStore,
                    preloadedStreamPoints: widget.preloadedStreamPoints,
                    exportBusy: _exportBusy,
                    onExport: _sessionRemoved ? null : _onExportThisSession,
                    onAllSessions: () => Navigator.of(context).maybePop(),
                  ),
                ] else if (isRun) ...[
                  RunSessionAnalytics(
                    workout: workout,
                    runSessionStore: widget.runSessionStore,
                    preloadedPaceSplits: widget.preloadedPaceSplits,
                    preloadedStreamPoints: widget.preloadedStreamPoints,
                    preloadedLeftovers: widget.preloadedLeftovers,
                    onAllSessions: () => Navigator.of(context).maybePop(),
                  ),
                ] else if (_isRacket) ...[
                  RacketSessionAnalytics(
                    workout: workout,
                    runSessionStore: widget.runSessionStore,
                    preloadedStreamPoints: widget.preloadedStreamPoints,
                    onAllSessions: () => Navigator.of(context).maybePop(),
                  ),
                ] else if (isSwim) ...[
                  SwimSessionCoachingFold(
                    workout: workout,
                    runSessionStore: widget.runSessionStore,
                    preloadedStreamPoints: widget.preloadedStreamPoints,
                    digDeeperOverride: widget.digDeeperOverride,
                    insightOverride: widget.swimInsightOverride,
                    lapsOverride: widget.swimLapsOverride,
                  ),
                  if (digDeeper) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Dig deeper',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _CountHintsCard(workout: workout),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'Session',
                      children: [
                        _Row('Start', _formatWhen(workout.startTime)),
                        _Row('End', _formatWhen(workout.endTime)),
                        _Row(
                          'Duration',
                          _formatDuration(workout.durationSec),
                        ),
                        _Row(
                          'Type',
                          '${workout.type} (${workoutTypeLabel(workout.type)})',
                        ),
                        if (workout.calories != null)
                          _Row('Calories', '${workout.calories} kcal'),
                        if (workout.distanceM != null)
                          _Row('Distance', '${workout.distanceM} m'),
                      ],
                    ),
                    if (swim != null) ...[
                      const SizedBox(height: 12),
                      _P0MetricsCard(session: swim),
                      if (analytics != null) ...[
                        const SizedBox(height: 12),
                        _SessionAnalyticsCard(analytics: analytics),
                      ],
                      const SizedBox(height: 12),
                      _DiagnosesLoader(workoutNumber: workout.number),
                    ],
                    if (workout.sampleCount != null &&
                        workout.sampleCount! > 0) ...[
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
                        subtitle:
                            '${workout.enrichmentTags!.length} tag(s) on wire',
                        children: [
                          for (final tag in workout.enrichmentTags!)
                            _Row('Tag ${tag.id}', 'len ${tag.len}'),
                        ],
                      ),
                    ],
                  ],
                ] else ...[
                  // Residual non-swim instrument dump (cycle/elliptical/etc).
                  _CountHintsCard(workout: workout),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Session',
                    children: [
                      _Row('Start', _formatWhen(workout.startTime)),
                      _Row('End', _formatWhen(workout.endTime)),
                      _Row('Duration', _formatDuration(workout.durationSec)),
                      _Row(
                        'Type',
                        '${workout.type} (${workoutTypeLabel(workout.type)})',
                      ),
                      if (workout.calories != null)
                        _Row('Calories', '${workout.calories} kcal'),
                      if (workout.distanceM != null)
                        _Row('Distance', '${workout.distanceM} m'),
                      if (workout.steps != null)
                        _Row('Steps', '${workout.steps}'),
                    ],
                  ),
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
                  if (workout.segments != null &&
                      workout.segments!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _LapTable(segments: workout.segments!),
                  ],
                  if (workout.sampleCount != null &&
                      workout.sampleCount! > 0) ...[
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
                      subtitle:
                          '${workout.enrichmentTags!.length} tag(s) on wire',
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

/// Run/Walk AppBar action: Export for AI (confirm → assemble → share).
class _RunSessionExportAction extends StatefulWidget {
  const _RunSessionExportAction({
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
  State<_RunSessionExportAction> createState() =>
      _RunSessionExportActionState();
}

class _RunSessionExportActionState extends State<_RunSessionExportAction> {
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
          'This creates a JSON dump of this Run/Walk session. It contains '
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
            subject: 'Fathom Run/Walk session export',
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

class _DiagnosesLoader extends StatelessWidget {
  const _DiagnosesLoader({required this.workoutNumber});

  final int workoutNumber;

  @override
  Widget build(BuildContext context) {
    Future<SwimDiagnosisReport>? future;
    try {
      future = sl<WorkoutHistoryRepository>().loadSwimDiagnosisReport(
        focusWorkoutNumber: workoutNumber,
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<SwimDiagnosisReport>(
      future: future,
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

class _ShareTcxAction extends StatefulWidget {
  const _ShareTcxAction({
    required this.workout,
    this.exportService,
    this.shareTcx,
  });

  final WorkoutSummary workout;
  final WorkoutTcxExportService? exportService;
  final Future<void> Function(File file)? shareTcx;

  @override
  State<_ShareTcxAction> createState() => _ShareTcxActionState();
}

class _ShareTcxActionState extends State<_ShareTcxAction> {
  bool _busy = false;

  WorkoutTcxExportService get _export {
    final injected = widget.exportService;
    if (injected != null) return injected;
    return sl<WorkoutTcxExportService>();
  }

  Future<void> _onShare() async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share as TCX?'),
        content: const Text(
          'Creates a TCX file of this workout for upload to Strava '
          '(strava.com/upload) or another app. Includes distance, duration, '
          'calories, and laps when available — not GPS or continuous HR. '
          'After you share it, recipients may keep copies; clearing the '
          'export cache does not revoke shared copies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final result = await _export.exportToCache(widget.workout);
    if (!mounted) return;

    if (!result.isSuccess || result.file == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'TCX export failed')),
      );
      return;
    }

    final file = result.file!;
    if (!_export.isSharePathAllowed(file)) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export path refused — not under cache')),
      );
      return;
    }

    try {
      final share = widget.shareTcx;
      if (share != null) {
        await share(file);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(
                file.path,
                mimeType: 'application/vnd.garmin.tcx+xml',
                name: file.uri.pathSegments.last,
              ),
            ],
            subject: 'Fathom workout TCX',
            text:
                'Upload at https://www.strava.com/upload/select (TCX). '
                'No GPS track — choose indoor/stationary if offered.',
          ),
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TCX ready — upload on Strava if you saved the file'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Share as TCX (Strava upload)',
      onPressed: _busy ? null : _onShare,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const StravaMarkIcon(),
    );
  }
}


bool _hasEnrichment(WorkoutSummary w) =>
    _dataFetchedStatus(w) == true ||
    _paceFetchedStatus(w) == true ||
    _segmentsFetchedStatus(w) == true ||
    (w.enrichmentTags != null && w.enrichmentTags!.isNotEmpty);

bool? _dataFetchedStatus(WorkoutSummary w) {
  if (w.dataCount == null || w.dataCount! <= 0) return null;
  // sampleFetch is authoritative when present — header sampleCount alone must
  // not claim fetched✓ after timeout/partial (AE6 honesty).
  final fetch = w.sampleFetch;
  if (fetch == 'timeout' || fetch == 'partial' || fetch == 'none') {
    return false;
  }
  if (fetch == 'ok') return true;
  // Prefer stream honesty / stored refs — sampleCount alone misses opaque
  // pages persisted without a rolled-up sample total (parity with pace).
  if (w.dataPagesStatus == WorkoutStreamHonesty.present ||
      w.dataPagesStatus == WorkoutStreamHonesty.partial) {
    return true;
  }
  if ((w.dataPagesStored ?? 0) > 0) return true;
  if (w.dataPagesStatus == WorkoutStreamHonesty.incomplete ||
      w.dataPagesStatus == WorkoutStreamHonesty.blocked) {
    return false;
  }
  if (w.sampleCount != null && w.sampleCount! > 0) return true;
  return w.enrichmentStatus == 'ok';
}

bool? _paceFetchedStatus(WorkoutSummary w) {
  if (w.paceCount == null || w.paceCount! <= 0) return null;
  // Prefer stream honesty / stored refs — soft-incomplete keeps enrichmentStatus
  // at `partial` even when pace blocks were persisted.
  if (w.paceBlocksStatus == WorkoutStreamHonesty.present ||
      w.paceBlocksStatus == WorkoutStreamHonesty.partial) {
    return true;
  }
  if ((w.paceBlocksStored ?? 0) > 0) return true;
  if (w.paceBlocksStatus == WorkoutStreamHonesty.incomplete ||
      w.paceBlocksStatus == WorkoutStreamHonesty.blocked) {
    return false;
  }
  return w.enrichmentStatus == 'ok';
}

bool? _segmentsFetchedStatus(WorkoutSummary w) {
  if (w.segmentsCount == null || w.segmentsCount! <= 0) return null;
  return w.segments != null && w.segments!.isNotEmpty;
}


/// Totals tag 0x18 is pool length in centimetres (catalog + 2500→25m probe).

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
