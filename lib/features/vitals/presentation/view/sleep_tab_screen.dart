import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/domain/sleep_analytics.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_state.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_detail_route.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_history_route.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_timing_chart.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_tonight_hero.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_trend_sparks.dart';

/// Recovery · Sleep: athlete overnight + timing/trends + history.
class SleepTabScreen extends StatefulWidget {
  const SleepTabScreen({super.key, this.repository});

  /// Optional override for widget tests.
  final VitalsRepository? repository;

  @override
  State<SleepTabScreen> createState() => _SleepTabScreenState();
}

class _SleepTabScreenState extends State<SleepTabScreen> {
  List<SleepStageSummary> _todayStages = const [];
  TruSleepSequenceSession? _todaySummary;
  SleepTrendBand? _trendBand;
  List<SleepTimingDay> _timingDays = const [];
  List<SleepSessionSummary> _recentRows = const [];
  Map<String, int> _recentScores = const {};
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
    TruSleepSequenceSession? summary;
    String? feel;
    SleepSessionSummary? surveySession;

    if (today != null) {
      stages = await _repo.loadSleepStages(today);
      summary = await _repo.loadTruSleepSummary(today);
      if (sleepCrossesLocalMidnight(today)) {
        feel = await _repo.loadFeelOnWake(today);
        surveySession = today;
      }
    }

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

    final overnights = recentOvernightSessions(sessions);
    final weekSummaries = <String, TruSleepSequenceSession?>{};
    await Future.wait(overnights.map((s) async {
      weekSummaries[s.mergeKey] = await _repo.loadTruSleepSummary(s);
    }));
    if (today != null && summary != null) {
      weekSummaries[today.mergeKey] = summary;
    }

    final points = <SleepTrendPoint>[
      for (final s in overnights)
        SleepTrendPoint(
          endUnix: s.endUnix,
          score: weekSummaries[s.mergeKey]?.sleepScore,
          hrv: weekSummaries[s.mergeKey]?.avgHrv,
        ),
    ];
    final band = buildSleepTrendBand(points);
    final timing = buildSleepTimingDays(
      overnights: overnights,
      summaries: weekSummaries,
    );

    // Recent list: last ~5 sessions ending most recently (naps + overnights).
    final recent = [...sessions]
      ..removeWhere((s) => s.beginUnix <= 0 || s.endUnix <= s.beginUnix)
      ..sort((a, b) => b.endUnix.compareTo(a.endUnix));
    final recentRows = recent.take(5).toList();
    final recentScores = <String, int>{};
    for (final s in recentRows) {
      final sum = weekSummaries[s.mergeKey] ??
          await _repo.loadTruSleepSummary(s);
      weekSummaries[s.mergeKey] = sum;
      final sc = sum?.sleepScore;
      if (sc != null && sc > 0) recentScores[s.mergeKey] = sc;
    }

    if (!mounted) return;
    setState(() {
      _todayStages = stages;
      _todaySummary = summary;
      _trendBand = band;
      _timingDays = timing;
      _recentRows = recentRows;
      _recentScores = recentScores;
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
          final weekAvg = _trendBand?.scoreMean;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _SyncPill(
                  syncing: syncing,
                  failed: failed,
                  everSynced: state.everSynced,
                  truSleep: _todaySummary?.isScientific == true,
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
                      'Sleep history.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.inkDim,
                      ),
                    ),
                  ),
                )
              else
                SleepTonightHero(
                  session: today,
                  summary: _todaySummary,
                  weekScoreAvg: weekAvg,
                  onViewDetails: () => SleepDetailRoute.go(context, today),
                ),
              if (_timingDays.any((d) => d.hasData)) ...[
                const SizedBox(height: 12),
                SleepTimingChart(days: _timingDays),
              ],
              if (_trendBand != null &&
                  (_trendBand!.latestScore != null ||
                      _trendBand!.latestHrv != null)) ...[
                const SizedBox(height: 12),
                SleepTrendSparks(band: _trendBand!),
              ],
              if (showSurvey) ...[
                const SizedBox(height: 12),
                _FeelOnWakeSurvey(onPick: _onSurveyPick),
              ],
              const SizedBox(height: 12),
              _AdvancedSleepMetricsCard(
                summary: _todaySummary,
                stages: _todayStages,
                session: today,
                onOpenDetail: today == null
                    ? null
                    : () => SleepDetailRoute.go(context, today),
              ),
              if (_recentRows.isNotEmpty) ...[
                const SizedBox(height: 12),
                _RecentNightsCard(
                  sessions: _recentRows,
                  scores: _recentScores,
                  onOpen: (s) => SleepDetailRoute.go(context, s),
                ),
              ],
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
              const SizedBox(height: 12),
              _SleepHistoryCta(
                onTap: () => SleepHistoryRoute.go(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecentNightsCard extends StatelessWidget {
  const _RecentNightsCard({
    required this.sessions,
    required this.scores,
    required this.onOpen,
  });

  final List<SleepSessionSummary> sessions;
  final Map<String, int> scores;
  final ValueChanged<SleepSessionSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recent nights',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final s in sessions)
              InkWell(
                onTap: () => onOpen(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sleepFormatShortDate(
                                sleepLocalFromUnix(s.endUnix),
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.ink,
                              ),
                            ),
                            Text(
                              '${sleepFormatWindow(s.beginUnix, s.endUnix)} · '
                              '${sleepCrossesLocalMidnight(s) ? 'overnight' : 'nap'}',
                              style: FathomTextStyles.mono(
                                fontSize: 10,
                                color: colors.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        sleepFormatDuration(s.durationSec),
                        style: FathomTextStyles.mono(
                          fontSize: 12,
                          color: colors.inkDim,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 36,
                        child: Text(
                          scores[s.mergeKey]?.toString() ??
                              (sleepCrossesLocalMidnight(s) ? '—' : 'nap'),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scores[s.mergeKey] != null
                                ? colors.ink
                                : colors.inkFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SleepHistoryCta extends StatelessWidget {
  const _SleepHistoryCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sleep history',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Browse by month · pick any night or nap',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({
    required this.syncing,
    required this.failed,
    required this.everSynced,
    this.truSleep = false,
  });

  final bool syncing;
  final bool failed;
  final bool everSynced;
  final bool truSleep;

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
    } else if (truSleep) {
      tint = colors.up;
      label = 'Synced · TruSleep';
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
        ? 'Pulling TruSleep SEQUENCE · stages · overnight averages.'
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
                              Text(opt.$1, style: const TextStyle(fontSize: 26)),
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

class _AdvancedSleepMetricsCard extends StatelessWidget {
  const _AdvancedSleepMetricsCard({
    required this.summary,
    required this.stages,
    required this.session,
    this.onOpenDetail,
  });

  final TruSleepSequenceSession? summary;
  final List<SleepStageSummary> stages;
  final SleepSessionSummary? session;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final scientific = summary?.isScientific == true;
    final cells = <(String, String)>[];

    if (scientific) {
      final s = summary!;
      if (s.usableLatencySec != null) {
        cells.add(('Latency', sleepFormatDuration(s.usableLatencySec!)));
      }
      if (s.usableDeepPart != null) {
        cells.add(('Deep cont.', '${s.usableDeepPart}'));
      }
      if (s.usableEfficiency != null) {
        cells.add(('Eff', '${s.usableEfficiency}%'));
      }
      if (s.avgHrv != null) cells.add(('HRV', '${s.avgHrv}'));
      if (s.avgHeartRate != null) cells.add(('Sleep HR', '${s.avgHeartRate}'));
      if (s.avgBreathRate != null) cells.add(('RR', '${s.avgBreathRate}'));
      if (s.avgOxygenSaturation != null) {
        cells.add(('SpO₂', '${s.avgOxygenSaturation}%'));
      }
      if (s.fallAsleepUnix != null && s.wakeupUnix != null) {
        cells.add((
          'Asleep',
          '${sleepFormatHm(sleepLocalFromUnix(s.fallAsleepUnix!))}–'
              '${sleepFormatHm(sleepLocalFromUnix(s.wakeupUnix!))}',
        ));
      }
    }

    if (stages.isNotEmpty) {
      final mins = stageMinutesOf(stages);
      if (mins.light > 0) cells.add(('Light', '${mins.light}m'));
      if (mins.deep > 0) cells.add(('Deep', '${mins.deep}m'));
      if (mins.rem > 0) cells.add(('REM', '${mins.rem}m'));
      if (mins.awake > 0) cells.add(('Awake', '${mins.awake}m'));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Advanced sleep metrics',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              scientific
                  ? 'TruSleep SEQUENCE · tonight'
                  : session == null
                      ? 'Available after an overnight Sync'
                      : 'Sync overnight for score, latency, deep continuity, '
                          'and overnight ANS averages',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            if (cells.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  for (final c in cells)
                    SizedBox(
                      width: 88,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.$2,
                            style: FathomTextStyles.mono(
                              fontSize: 13,
                              color: colors.ink,
                            ),
                          ),
                          Text(
                            c.$1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Landmarks · latency · deep continuity · efficiency · '
              'HRV / sleep HR / RR / SpO₂ · stage mix. '
              'No invented Quality score · no fake waveforms.',
              style: FathomTextStyles.mono(
                fontSize: 11,
                color: colors.inkFaint,
              ),
            ),
            if (onOpenDetail != null && scientific) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onOpenDetail,
                  child: const Text('Open night details'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
