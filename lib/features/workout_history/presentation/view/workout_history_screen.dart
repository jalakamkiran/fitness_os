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
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_row.dart';

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
                  WorkoutSportTab.swim => _SwimPanel(workouts: state.workouts),
                  WorkoutSportTab.run => const _EmptySportPanel(
                      title: 'Run',
                      body:
                          'Scaffolding only. Run sessions will list here when '
                          'the sport lane opens — no charts on the list.',
                    ),
                  WorkoutSportTab.strength => const _EmptySportPanel(
                      title: 'Strength',
                      body:
                          'Scaffolding only. Strength history stays off Swim '
                          'and never borrows vitals trends.',
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

class _SwimPanel extends StatelessWidget {
  const _SwimPanel({required this.workouts});

  final List<WorkoutSummary> workouts;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final swim = workouts.where((w) => isSwimWorkout(w.type)).toList();

    if (swim.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No swim sessions yet.\n'
            'Complete a pool swim on the watch, then Sync.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.inkDim),
          ),
        ),
      );
    }

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
              '${swim.length} · pool',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < swim.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          SwimSessionRow(
            workout: swim[i],
            onTap: () => WorkoutDetailRoute.go(context, swim[i]),
          ),
        ],
      ],
    );
  }
}

class _EmptySportPanel extends StatelessWidget {
  const _EmptySportPanel({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.inkDim),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.bgElev,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.line),
            ),
            child: Text(
              'Empty · OK',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
