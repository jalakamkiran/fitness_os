import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_bloc.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_event.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_state.dart';
import 'package:fitness_os/features/workout_history/presentation/view/coach_settings_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_route.dart';

class WorkoutHistoryScreen extends StatelessWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<WorkoutHistoryBloc>()..add(const WorkoutHistoryStarted()),
      child: const _WorkoutHistoryView(),
    );
  }
}

class _WorkoutHistoryView extends StatelessWidget {
  const _WorkoutHistoryView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workouts'),
        actions: [
          IconButton(
            tooltip: 'Reasoner settings',
            icon: const Icon(Icons.psychology_outlined),
            onPressed: () => CoachSettingsRoute.go(context),
          ),
        ],
      ),
      body: BlocBuilder<WorkoutHistoryBloc, WorkoutHistoryState>(
        builder: (context, state) {
          final syncing = state.phase == WorkoutHistoryPhase.syncing;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      state.gateAPassed
                          ? 'Gate A unlocked — Sync pulls full workout history '
                              '(from mid-2022 through now), not just new ones.'
                          : 'Gate A incomplete — finish the interrupt checklist on Pairing first.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: !state.gateAPassed || syncing
                          ? null
                          : () => context
                              .read<WorkoutHistoryBloc>()
                              .add(const WorkoutHistorySyncRequested()),
                      icon: syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        syncing ? 'Syncing history…' : 'Sync all history',
                      ),
                    ),
                    if (state.message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.message!,
                        style: TextStyle(
                          color: state.phase == WorkoutHistoryPhase.stuck
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const _SwimTrendsStrip(),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: state.workouts.isEmpty
                    ? const Center(
                        child: Text(
                          'No workouts stored yet.\n'
                          'Complete a workout on the watch, then Sync.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: state.workouts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final w = state.workouts[index];
                          return ListTile(
                            title: Text(_typeLabel(w.type)),
                            subtitle: Text(
                              '${_formatWhen(w.startTime)} · ${_formatDuration(w.durationSec)}'
                              '${w.distanceM != null ? ' · ${w.distanceM} m' : ''}'
                              '${_enrichmentHint(w)}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => WorkoutDetailRoute.go(context, w),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SwimTrendsStrip extends StatelessWidget {
  const _SwimTrendsStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<SwimDiagnosisReport>(
      future: sl<WorkoutHistoryRepository>().loadSwimDiagnosisReport(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final report = snap.data!;
        final t = report.trends;
        if (t.sessionCount <= 0) return const SizedBox.shrink();
        final top = report.trendDiagnoses.isNotEmpty
            ? report.trendDiagnoses.first
            : null;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Swim trends',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${t.sessionCount} session${t.sessionCount == 1 ? '' : 's'}'
                '${t.totalDistanceM != null ? ' · ${t.totalDistanceM} m' : ''}'
                '${t.totalMovingSec != null ? ' · ${_formatDuration(t.totalMovingSec!)} moving' : ''}',
                style: theme.textTheme.bodySmall,
              ),
              if (top != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${top.title}: ${top.summary}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _typeLabel(int type) {
  // Frozen from owner 25m pool probe (2026-07-23): type=6 is pool (GB=6 / OW=8).
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
    140: 'Strength', // observed GT5-A07 strength session
  };
  return names[type] ?? 'Workout type $type';
}

String _formatWhen(int unixSec) {
  if (unixSec <= 0) return 'unknown time';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

String _enrichmentHint(WorkoutSummary w) {
  final parts = <String>[];
  if (w.dataCount != null && w.dataCount! > 0) parts.add('d${w.dataCount}');
  if (w.paceCount != null && w.paceCount! > 0) parts.add('p${w.paceCount}');
  if (w.segmentsCount != null && w.segmentsCount! > 0) {
    parts.add('s${w.segmentsCount}');
  }
  if (parts.isEmpty) return '';
  return ' · ${parts.join(' ')}';
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
