import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/morning_wellness.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_state.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_detail_route.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_history_route.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/morning_wellness_copy.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_session_card.dart';

/// Recovery · Sleep list (S0): sync pill, Hooper-4 survey, today card, history.
class SleepTabScreen extends StatefulWidget {
  const SleepTabScreen({super.key, this.repository});

  /// Optional override for widget tests.
  final VitalsRepository? repository;

  @override
  State<SleepTabScreen> createState() => _SleepTabScreenState();
}

class _SleepTabScreenState extends State<SleepTabScreen> {
  List<SleepStageSummary> _todayStages = const [];
  MorningWellness? _storedWellness;
  bool _surveyLoading = true;
  SleepSessionSummary? _surveySession;
  final Map<String, int> _draft = {};
  bool _saving = false;

  VitalsRepository get _repo => widget.repository ?? sl<VitalsRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateFromState());
  }

  Future<void> _hydrateFromState() async {
    if (!mounted) return;
    final state = context.read<VitalsBloc>().state;
    await _loadExtras(state.sleepSessions);
  }

  Future<void> _loadExtras(List<SleepSessionSummary> sessions) async {
    final today = todaysSleepSession(sessions);
    List<SleepStageSummary> stages = const [];
    MorningWellness? wellness;
    SleepSessionSummary? surveySession;

    // Today’s overnight only (no historical catch-up). Nap fallback ignored.
    if (today != null) {
      stages = await _repo.loadSleepStages(today);
      if (sleepCrossesLocalMidnight(today)) {
        surveySession = today;
        wellness = await _repo.loadMorningWellness(today);
      }
    }

    if (!mounted) return;
    setState(() {
      _todayStages = stages;
      _storedWellness = wellness;
      _surveySession = surveySession;
      _draft.clear();
      _surveyLoading = false;
    });
  }

  int get _draftAnswered => _draft.length;

  Future<void> _onDimensionPick(String key, int score) async {
    if (_saving) return;
    setState(() => _draft[key] = score);
    if (_draftAnswered < MorningWellnessCopy.dimensions.length) return;

    final session = _surveySession;
    if (session == null) return;
    final wellness = MorningWellness(
      sleepQuality: _draft['sleepQuality']!,
      fatigue: _draft['fatigue']!,
      soreness: _draft['soreness']!,
      stress: _draft['stress']!,
    );
    if (!wellness.isComplete) return;

    setState(() => _saving = true);
    await _repo.saveMorningWellness(session, wellness);
    final reloaded = await _repo.loadMorningWellness(session);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (reloaded != null) {
        _storedWellness = reloaded;
        _draft.clear();
      }
      // Save failure → keep draft and survey visible.
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return BlocListener<VitalsBloc, VitalsState>(
      listenWhen: (prev, next) => prev.sleepSessions != next.sleepSessions,
      listener: (context, state) {
        setState(() => _surveyLoading = true);
        _loadExtras(state.sleepSessions);
      },
      child: BlocBuilder<VitalsBloc, VitalsState>(
        builder: (context, state) {
          final today = todaysSleepSession(state.sleepSessions);
          final syncing = state.phase == VitalsPhase.syncing;
          final failed = state.phase == VitalsPhase.stuck ||
              (state.message != null &&
                  state.message!.toLowerCase().contains('fail'));
          final overnightCandidate = _surveySession != null &&
              sleepCrossesLocalMidnight(_surveySession!);
          // Presence gate: not syncing + today’s overnight + incomplete.
          final showSurvey = !syncing &&
              !_surveyLoading &&
              overnightCandidate &&
              _storedWellness == null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _SyncPill(
                  syncing: syncing,
                  failed: failed,
                  everSynced: state.everSynced,
                ),
              ),
              if (showSurvey) ...[
                const SizedBox(height: 12),
                _Hooper4Survey(
                  draft: Map<String, int>.from(_draft),
                  saving: _saving,
                  onPick: _onDimensionPick,
                ),
              ],
              const SizedBox(height: 12),
              if (today == null && state.sleepSessions.isEmpty)
                _EmptySleepCard(syncing: syncing, failed: failed)
              else if (today == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No sleep ending today yet. Earlier nights are under '
                      'historic sleep data.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.inkDim,
                      ),
                    ),
                  ),
                )
              else
                SleepSessionCard(
                  session: today,
                  stages: _todayStages,
                  kicker: 'Today · sleep',
                  showDetailsCta: true,
                  onViewDetails: () => SleepDetailRoute.go(context, today),
                ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  title: Text(
                    'View historic sleep data',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right, color: colors.inkFaint),
                  onTap: () => SleepHistoryRoute.go(context),
                ),
              ),
              const SizedBox(height: 12),
              const _AdvancedLockedChrome(),
              if (state.sleepSessions.isNotEmpty && today != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: state.syncDisabled
                      ? null
                      : () => context
                          .read<VitalsBloc>()
                          .add(const VitalsSyncRequested()),
                  child: Text(syncing ? 'Syncing…' : 'Sync sleep'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({
    required this.syncing,
    required this.failed,
    required this.everSynced,
  });

  final bool syncing;
  final bool failed;
  final bool everSynced;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final Color tint;
    final String label;
    if (syncing) {
      tint = colors.amber;
      label = 'Syncing';
    } else if (failed) {
      tint = colors.hot;
      label = 'Sync failed';
    } else if (!everSynced) {
      tint = colors.inkFaint;
      label = 'Never synced';
    } else {
      tint = colors.accent;
      label = 'Synced';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: FathomTextStyles.mono(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.inkDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySleepCard extends StatelessWidget {
  const _EmptySleepCard({required this.syncing, required this.failed});

  final bool syncing;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final title = syncing
        ? 'Syncing sleep'
        : failed
            ? 'Sync failed'
            : 'No sleep yet';
    final body = syncing
        ? 'Pulling messages · stages first · HR window next · '
            'FileDownload last (non-blocking).'
        : failed
            ? 'No prior sleep stored. Retry Sync when the watch is nearby.'
            : 'No sleep sessions stored yet. Wear overnight '
                '(prefer night 2 after pairing), then Sync.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sleep',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.inkDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hooper4Survey extends StatelessWidget {
  const _Hooper4Survey({
    required this.draft,
    required this.saving,
    required this.onPick,
  });

  final Map<String, int> draft;
  final bool saving;
  final void Function(String key, int score) onPick;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final answered = draft.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Morning wellness',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.inkFaint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$answered/4 answered',
                  style: FathomTextStyles.mono(
                    fontSize: 11,
                    color: colors.inkFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'How did last night land?',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 12),
            for (final dim in MorningWellnessCopy.dimensions) ...[
              _DimensionRow(
                title: dim.title,
                lowLabel: dim.lowLabel,
                highLabel: dim.highLabel,
                selected: draft[dim.key],
                enabled: !saving,
                onPick: (score) => onPick(dim.key, score),
              ),
              if (dim.key != MorningWellnessCopy.dimensions.last.key)
                const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _DimensionRow extends StatelessWidget {
  const _DimensionRow({
    required this.title,
    required this.lowLabel,
    required this.highLabel,
    required this.selected,
    required this.enabled,
    required this.onPick,
  });

  final String title;
  final String lowLabel;
  final String highLabel;
  final int? selected;
  final bool enabled;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final unanswered = selected == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: unanswered ? colors.inkDim : colors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                '1 · $lowLabel',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.inkFaint,
                ),
              ),
            ),
            Text(
              '7 · $highLabel',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var score = MorningWellness.minScore;
                score <= MorningWellness.maxScore;
                score++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Semantics(
                    button: true,
                    label: '$title $score',
                    child: InkWell(
                      onTap: enabled ? () => onPick(score) : null,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected == score
                                ? colors.accent
                                : colors.line,
                            width: selected == score ? 1.5 : 1,
                          ),
                          color: selected == score
                              ? colors.bgElev
                              : colors.bg,
                        ),
                        child: Text(
                          '$score',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AdvancedLockedChrome extends StatelessWidget {
  const _AdvancedLockedChrome();

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Coming later',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Advanced sleep metrics — unlock soon',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.inkDim,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'no fake metrics · quality score deferred',
              style: FathomTextStyles.mono(
                fontSize: 11,
                color: colors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
