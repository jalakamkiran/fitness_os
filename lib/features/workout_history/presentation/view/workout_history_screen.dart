import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_bloc.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_event.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_state.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_route.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/sport_tabs.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/workout_session_row.dart';

class WorkoutHistoryScreen extends StatelessWidget {
  const WorkoutHistoryScreen({super.key, this.bloc});

  /// Optional override for widget tests.
  final WorkoutHistoryBloc? bloc;

  @override
  Widget build(BuildContext context) {
    final override = bloc;
    if (override != null) {
      return BlocProvider.value(
        value: override,
        child: const _WorkoutHistoryView(),
      );
    }
    return BlocProvider(
      create: (_) =>
          sl<WorkoutHistoryBloc>()..add(const WorkoutHistoryStarted()),
      child: const _WorkoutHistoryView(),
    );
  }
}

class _WorkoutHistoryView extends StatefulWidget {
  const _WorkoutHistoryView();

  @override
  State<_WorkoutHistoryView> createState() => _WorkoutHistoryViewState();
}

class _WorkoutHistoryViewState extends State<_WorkoutHistoryView> {
  WorkoutSportTab _sport = WorkoutSportTab.swim;

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

class _SportSessionPanel extends StatelessWidget {
  const _SportSessionPanel({
    required this.workouts,
    required this.match,
    required this.countSuffix,
    required this.emptyBody,
    required this.thirdLabel,
    required this.thirdValue,
  });

  final List<WorkoutSummary> workouts;
  final bool Function(int type) match;
  final String countSuffix;
  final String emptyBody;
  final String thirdLabel;
  final String Function(WorkoutSummary workout) thirdValue;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final filtered = workouts.where((w) => match(w.type)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
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
