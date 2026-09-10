import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/data/strength_session_export_service.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_bloc.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_event.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_state.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/sport_tabs.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/workout_session_row.dart';

class WorkoutHistoryScreen extends StatelessWidget {
  const WorkoutHistoryScreen({
    super.key,
    this.bloc,
    this.exportService,
    this.exportAllOverride,
    this.exportBusyOverride,
    this.shareExport,
  });

  /// Optional override for widget tests.
  final WorkoutHistoryBloc? bloc;

  /// Test / DI seam for the Strength-tab all-sessions extra.
  final StrengthSessionExportService? exportService;

  /// Test seam — when set, used instead of exportAllStrengthSessionsToCache.
  final Future<StrengthSessionExportResult> Function()? exportAllOverride;

  /// Test seam — when set, used instead of [StrengthSessionExportService.isBusy].
  final bool Function()? exportBusyOverride;

  /// Test seam — production uses [SharePlus].
  final Future<void> Function(File file)? shareExport;

  @override
  Widget build(BuildContext context) {
    final override = bloc;
    if (override != null) {
      return BlocProvider.value(
        value: override,
        child: _WorkoutHistoryView(
          exportService: exportService,
          exportAllOverride: exportAllOverride,
          exportBusyOverride: exportBusyOverride,
          shareExport: shareExport,
        ),
      );
    }
    return BlocProvider(
      create: (_) =>
          sl<WorkoutHistoryBloc>()..add(const WorkoutHistoryStarted()),
      child: _WorkoutHistoryView(
        exportService: exportService,
        exportAllOverride: exportAllOverride,
        exportBusyOverride: exportBusyOverride,
        shareExport: shareExport,
      ),
    );
  }
}

class _WorkoutHistoryView extends StatefulWidget {
  const _WorkoutHistoryView({
    this.exportService,
    this.exportAllOverride,
    this.exportBusyOverride,
    this.shareExport,
  });

  final StrengthSessionExportService? exportService;
  final Future<StrengthSessionExportResult> Function()? exportAllOverride;
  final bool Function()? exportBusyOverride;
  final Future<void> Function(File file)? shareExport;

  @override
  State<_WorkoutHistoryView> createState() => _WorkoutHistoryViewState();
}

class _WorkoutHistoryViewState extends State<_WorkoutHistoryView> {
  WorkoutSportTab _sport = WorkoutSportTab.swim;
  bool _exportBusy = false;

  StrengthSessionExportService get _export =>
      widget.exportService ?? sl<StrengthSessionExportService>();

  bool get _serviceBusy =>
      widget.exportBusyOverride?.call() ?? _export.isBusy;

  Future<StrengthSessionExportResult> _runExportAll() =>
      widget.exportAllOverride?.call() ??
      _export.exportAllStrengthSessionsToCache();

  Future<void> _onExportAllStrength(int sessionCount) async {
    if (_exportBusy) return;
    if (sessionCount <= 0) return;
    if (_serviceBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Export blocked — wait for sync or Forget to finish, then try again.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export all strength sessions?'),
        content: Text(
          'This creates a JSON file of $sessionCount strength session'
          '${sessionCount == 1 ? '' : 's'} stored on this device, including '
          'leftover Totals bytes, HR sample points, and recovery-HR blobs '
          'when present. It contains non-anonymized health data. '
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

    setState(() => _exportBusy = true);

    final result = await _runExportAll();
    if (!mounted) return;

    if (!result.isSuccess || result.file == null) {
      setState(() => _exportBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Export failed')),
      );
      return;
    }

    final file = result.file!;
    final sharePath = file.absolute.path;
    if (!sharePath.contains(
      '/${StrengthSessionExportService.exportCacheDirName}/',
    )) {
      setState(() => _exportBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export path refused — not under export cache'),
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
            subject: 'Fathom strength sessions export',
          ),
        );
      }
      if (!mounted) return;
      setState(() => _exportBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export ready')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exportBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fathom',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.ink,
              ),
            ),
            Text(
              'Workouts · history',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        actions: [
          BlocBuilder<WorkoutHistoryBloc, WorkoutHistoryState>(
            builder: (context, state) {
              final syncing = state.phase == WorkoutHistoryPhase.syncing;
              return IconButton(
                tooltip: 'Sync all history',
                onPressed: !state.gateAPassed || syncing
                    ? null
                    : () => context
                        .read<WorkoutHistoryBloc>()
                        .add(const WorkoutHistorySyncRequested()),
                icon: syncing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.accent,
                        ),
                      )
                    : const Icon(Icons.sync),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<WorkoutHistoryBloc, WorkoutHistoryState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SportTabs(
                  selected: _sport,
                  onSelected: (tab) => setState(() => _sport = tab),
                ),
              ),
              if (state.message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    state.message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: state.phase == WorkoutHistoryPhase.stuck
                          ? colors.hot
                          : colors.inkDim,
                    ),
                  ),
                ),
              Expanded(
                child: switch (_sport) {
                  WorkoutSportTab.swim => _SportSessionPanel(
                      workouts: state.workouts,
                      match: isSwimWorkout,
                      countSuffix: 'pool',
                      emptyBody:
                          'No swim sessions yet.\n'
                          'Complete a pool swim on the watch, then Sync.',
                      thirdLabel: 'SWOLF',
                      thirdValue: (w) => w.avgSwolf?.toString() ?? '—',
                    ),
                  WorkoutSportTab.run => _SportSessionPanel(
                      workouts: state.workouts,
                      match: isRunWorkout,
                      countSuffix: 'run',
                      emptyBody:
                          'No run sessions yet.\n'
                          'Complete a run on the watch, then Sync.',
                      thirdLabel: 'Calories',
                      thirdValue: (w) =>
                          w.calories == null ? '—' : '${w.calories}',
                    ),
                  WorkoutSportTab.strength => _SportSessionPanel(
                      workouts: state.workouts,
                      match: isStrengthWorkout,
                      countSuffix: 'strength',
                      emptyBody:
                          'No strength sessions yet.\n'
                          'Complete a strength workout on the watch, then Sync.',
                      thirdLabel: 'Calories',
                      thirdValue: (w) =>
                          w.calories == null ? '—' : '${w.calories}',
                      allSessionsExport: _StrengthAllSessionsExport(
                        workouts: state.workouts,
                        exportBusy: _exportBusy,
                        onExport: _onExportAllStrength,
                      ),
                    ),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Explicit all-sessions extra — Strength tab only (not the default prove CTA).
class _StrengthAllSessionsExport extends StatelessWidget {
  const _StrengthAllSessionsExport({
    required this.workouts,
    required this.exportBusy,
    required this.onExport,
  });

  final List<WorkoutSummary> workouts;
  final bool exportBusy;
  final Future<void> Function(int sessionCount) onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FathomColors.of(context);
    final strengthCount =
        workouts.where((w) => isStrengthWorkout(w.type)).length;
    final enabled = strengthCount > 0 && !exportBusy;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: enabled ? () => onExport(strengthCount) : null,
            icon: exportBusy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accent,
                    ),
                  )
                : const Icon(Icons.ios_share, size: 18),
            label: const Text('Export all strength sessions'),
          ),
          if (strengthCount == 0) ...[
            const SizedBox(height: 6),
            Text(
              'No strength sessions on this device to export.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.inkDim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SportSessionPanel extends StatelessWidget {
  const _SportSessionPanel({
    required this.workouts,
    required this.match,
    required this.countSuffix,
    required this.emptyBody,
    required this.thirdLabel,
    required this.thirdValue,
    this.allSessionsExport,
  });

  final List<WorkoutSummary> workouts;
  final bool Function(int type) match;
  final String countSuffix;
  final String emptyBody;
  final String thirdLabel;
  final String Function(WorkoutSummary workout) thirdValue;
  final Widget? allSessionsExport;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final filtered = workouts.where((w) => match(w.type)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (allSessionsExport != null) allSessionsExport!,
        Row(
          children: [
            Expanded(
              child: Text(
                'Sessions',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            Text(
              '${filtered.length} · $countSuffix',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
            child: Text(
              emptyBody,
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: colors.inkDim),
            ),
          )
        else
          for (var i = 0; i < filtered.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            WorkoutSessionRow(
              workout: filtered[i],
              thirdLabel: thirdLabel,
              thirdValue: thirdValue(filtered[i]),
              onTap: () => WorkoutDetailRoute.go(context, filtered[i]),
            ),
          ],
      ],
    );
  }
}
