import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/data/strength_session_export_service.dart';
import 'package:fitness_os/features/workout_history/domain/strength_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_bloc.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_event.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_state.dart';
import 'package:fitness_os/features/workout_history/domain/huawei_workout_types.dart'
    show isSportsWorkout, workoutTypeLabel, workoutTypeCategory;
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart'
    hide workoutTypeLabel;
import 'package:fitness_os/features/workout_history/presentation/widgets/sport_tabs.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/sports_filter_chips.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/workout_session_row.dart';

List<({String label, String value})> strengthSessionMeta(WorkoutSummary w) {
  return [
    (label: 'Load', value: w.load?.toString() ?? '—'),
    (label: 'Recovery', value: formatRecoveryMinutes(w.recoveryTime) ?? '—'),
    (label: 'Cal', value: w.calories?.toString() ?? '—'),
  ];
}

List<({String label, String value})> runSessionMeta(WorkoutSummary w) {
  return [
    (label: 'Distance', value: formatDistanceKm(w.distanceM) ?? '—'),
    (label: 'Time', value: formatDurationClock(w.durationSec)),
    (
      label: 'Pace',
      value: formatAvgPaceSecPerKm(w.distanceM, w.durationSec) ?? '—',
    ),
  ];
}

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
  Set<int> _sportsFilter = {}; // Empty = all sports
  bool _exportBusy = false;
  List<WorkoutSummary> _lastWorkouts = [];

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
          'session totals and heart-rate samples when available. '
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

  WorkoutSportTab _tabForWorkout(int type) {
    if (isSwimWorkout(type)) return WorkoutSportTab.swim;
    if (isRunWorkout(type)) return WorkoutSportTab.run;
    if (isStrengthWorkout(type)) return WorkoutSportTab.gym;
    if (isSportsWorkout(type)) return WorkoutSportTab.sports;
    return WorkoutSportTab.sports; // Default to sports for unknown types
  }

  void _showSyncSnackBar(
    WorkoutHistoryState state,
    List<WorkoutSummary> newWorkouts,
  ) {
    if (!mounted) return;

    final count = newWorkouts.length;
    final types = newWorkouts.map((w) => workoutTypeLabel(w.type)).toSet();
    final typesList = types.take(3).join(', ');
    final moreCount = types.length > 3 ? ' +${types.length - 3} more' : '';

    String message;
    if (count == 1) {
      final w = newWorkouts.first;
      message =
          'Full-history sync returned 1 workout (${workoutTypeLabel(w.type)} #${w.number}). '
          'Sessions the watch already marked synced may not be re-sent.';
    } else {
      message =
          'Full-history sync returned $count workouts ($typesList$moreCount). '
          'Sessions the watch already marked synced may not be re-sent.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
      ),
    );
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
              final canSync = state.gateAPassed && !syncing;
              if (syncing) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    ),
                  ),
                );
              }
              return PopupMenuButton<_WorkoutSyncMenu>(
                tooltip: 'Sync',
                enabled: canSync,
                icon: Icon(
                  Icons.sync,
                  color: canSync ? null : colors.inkFaint,
                ),
                onSelected: (choice) async {
                  if (!canSync || !context.mounted) return;
                  if (choice == _WorkoutSyncMenu.delta) {
                    context.read<WorkoutHistoryBloc>().add(
                          const WorkoutHistorySyncRequested(),
                        );
                    return;
                  }
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Force Sync (full history)?'),
                      content: const Text(
                        'Asks the watch for workouts since mid-2022 '
                        '(not just since the last Sync cursor). Use this '
                        'when a session is on-wrist but missing here, or '
                        'when Load / Recovery look empty after a bad Sync.\n\n'
                        'Wait until the watch shows linked / connected — if '
                        'Force Sync runs while still authenticating it is '
                        'skipped and older strength sessions are not repaired.\n\n'
                        'Still hint-gated: does not force-empty Data/Pace. '
                        'The watch may still omit sessions it already '
                        'marked synced.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Force Sync'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    context.read<WorkoutHistoryBloc>().add(
                          const WorkoutHistorySyncRequested(
                            forceFullHistory: true,
                          ),
                        );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _WorkoutSyncMenu.delta,
                    child: Text('Sync'),
                  ),
                  PopupMenuItem(
                    value: _WorkoutSyncMenu.forceFullHistory,
                    child: Text('Force Sync (full history)'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<WorkoutHistoryBloc, WorkoutHistoryState>(
        listener: (context, state) {
          // Auto-select tab of most recent synced workout
          if (state.workouts.isNotEmpty && state.workouts != _lastWorkouts) {
            final newWorkouts = state.workouts
                .where((w) => !_lastWorkouts.any((old) => old.number == w.number))
                .toList();
            
            if (newWorkouts.isNotEmpty) {
              final mostRecent = newWorkouts.first;
              final newTab = _tabForWorkout(mostRecent.type);
              if (newTab != _sport) {
                setState(() => _sport = newTab);
              }
              
              // Show improved sync feedback SnackBar
              _showSyncSnackBar(state, newWorkouts);
            }
            
            _lastWorkouts = state.workouts;
          }
        },
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SportTabs(
                  selected: _sport,
                  onSelected: (tab) => setState(() {
                    _sport = tab;
                    if (tab == WorkoutSportTab.sports) {
                      _sportsFilter = {}; // Reset filter when switching to Sports tab
                    }
                  }),
                ),
              ),
              if (_sport == WorkoutSportTab.sports)
                SportsFilterChips(
                  availableTypes: state.workouts
                      .where((w) => isSportsWorkout(w.type))
                      .map((w) => w.type)
                      .toSet(),
                  selectedTypes: _sportsFilter,
                  onSelectionChanged: (types) =>
                      setState(() => _sportsFilter = types),
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
                      countSuffix: 'run/walk',
                      emptyBody:
                          'No run or walk sessions yet.\n'
                          'Complete one on the watch, then Sync.',
                      thirdLabel: 'Pace',
                      thirdValue: (w) =>
                          formatAvgPaceSecPerKm(w.distanceM, w.durationSec) ??
                          '—',
                      metaColumns: runSessionMeta,
                    ),
                  WorkoutSportTab.gym => _SportSessionPanel(
                      workouts: state.workouts,
                      match: isStrengthWorkout,
                      countSuffix: 'gym/strength',
                      emptyBody:
                          'No gym sessions yet.\n'
                          'Complete a strength workout on the watch, then Sync.',
                      thirdLabel: 'Calories',
                      thirdValue: (w) =>
                          w.calories == null ? '—' : '${w.calories}',
                      metaColumns: strengthSessionMeta,
                      allSessionsExport: _StrengthAllSessionsExport(
                        workouts: state.workouts,
                        exportBusy: _exportBusy || _serviceBusy,
                        onExport: _onExportAllStrength,
                      ),
                    ),
                  WorkoutSportTab.sports => _SportSessionPanel(
                      workouts: state.workouts,
                      match: (type) {
                        if (!isSportsWorkout(type)) return false;
                        if (_sportsFilter.isEmpty) return true;
                        return _sportsFilter.contains(type);
                      },
                      countSuffix: 'sports',
                      emptyBody: _sportsFilter.isEmpty
                          ? 'No sports sessions yet.\n'
                              'Complete a racket sport, ball sport, or other activity\n'
                              'on the watch, then Sync.'
                          : 'No matching sports sessions.\n'
                              'Try selecting different sports or tap "All".',
                      thirdLabel: 'Sport',
                      thirdValue: (w) => workoutTypeLabel(w.type),
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
    this.metaColumns,
    this.allSessionsExport,
  });

  final List<WorkoutSummary> workouts;
  final bool Function(int type) match;
  final String countSuffix;
  final String emptyBody;
  final String thirdLabel;
  final String Function(WorkoutSummary workout) thirdValue;
  final List<({String label, String value})> Function(WorkoutSummary workout)?
      metaColumns;
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
              metaColumns: metaColumns?.call(filtered[i]),
              onTap: () => WorkoutDetailRoute.go(context, filtered[i]),
            ),
          ],
      ],
    );
  }
}

enum _WorkoutSyncMenu { delta, forceFullHistory }
