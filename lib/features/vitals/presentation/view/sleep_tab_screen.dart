import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_state.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_detail_route.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_history_route.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_session_card.dart';

/// Recovery · Sleep list (S0): sync pill, today card, survey, history, locked.
class SleepTabScreen extends StatefulWidget {
  const SleepTabScreen({super.key, this.repository});

  /// Optional override for widget tests.
  final VitalsRepository? repository;

  @override
  State<SleepTabScreen> createState() => _SleepTabScreenState();
}

class _SleepTabScreenState extends State<SleepTabScreen> {
  List<SleepStageSummary> _todayStages = const [];
  String? _feelAnswer;
  bool _surveyLoading = true;
  SleepSessionSummary? _surveySession;

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
    String? feel;
    SleepSessionSummary? surveySession;

    if (today != null) {
      stages = await _repo.loadSleepStages(today);
      if (sleepCrossesLocalMidnight(today)) {
        feel = await _repo.loadFeelOnWake(today);
        surveySession = today;
      }
    }

    // Prefer today's overnight; else most recent unanswered overnight.
    if (surveySession == null) {
      for (final s in sessions) {
        if (!sleepCrossesLocalMidnight(s)) continue;
        final existing = await _repo.loadFeelOnWake(s);
        if (existing == null) {
          surveySession = s;
          feel = null;
          break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _todayStages = stages;
      _feelAnswer = feel;
      _surveySession = surveySession;
      _surveyLoading = false;
    });
  }

  Future<void> _onSurveyPick(String answer) async {
    final session = _surveySession;
    if (session == null) return;
    await _repo.saveFeelOnWake(session, answer);
    if (!mounted) return;
    setState(() => _feelAnswer = answer);
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
          final showSurvey = !_surveyLoading &&
              _surveySession != null &&
              _feelAnswer == null &&
              sleepCrossesLocalMidnight(_surveySession!);

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
              if (showSurvey) ...[
                const SizedBox(height: 12),
                _FeelOnWakeSurvey(onPick: _onSurveyPick),
              ],
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

class _FeelOnWakeSurvey extends StatelessWidget {
  const _FeelOnWakeSurvey({required this.onPick});

  final ValueChanged<String> onPick;

  static const _options = <(String emoji, String label, String key)>[
    ('😫', 'Awful', 'awful'),
    ('😕', 'Meh', 'meh'),
    ('😐', 'Okay', 'okay'),
    ('🙂', 'Good', 'good'),
    ('😄', 'Great', 'great'),
  ];

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
              'Feel on wake',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'How do you feel waking up?',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final opt in _options)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        onTap: () => onPick(opt.$3),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.line),
                          ),
                          child: Column(
                            children: [
                              Text(opt.$1, style: const TextStyle(fontSize: 20)),
                              const SizedBox(height: 4),
                              Text(
                                opt.$2,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.inkDim,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
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
