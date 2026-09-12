import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/domain/sleep_analytics.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_history_route.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_contributors.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_hypnogram.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_stage_mix.dart';

/// Sleep session detail: TruSleep summary + advanced metrics + stages.
class SleepDetailScreen extends StatefulWidget {
  const SleepDetailScreen({
    super.key,
    required this.session,
    this.repository,
  });

  final SleepSessionSummary session;

  /// Optional override for widget tests.
  final VitalsRepository? repository;

  @override
  State<SleepDetailScreen> createState() => _SleepDetailScreenState();
}

class _SleepDetailScreenState extends State<SleepDetailScreen> {
  bool _loading = true;
  List<SleepStageSummary> _stages = const [];
  TruSleepSequenceSession? _summary;
  double? _weekScoreAvg;

  VitalsRepository get _repo => widget.repository ?? sl<VitalsRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stages = await _repo.loadSleepStages(widget.session);
    final summary = await _repo.loadTruSleepSummary(widget.session);
    final all = await _repo.loadSleepSessions();
    final overnights = recentOvernightSessions(all);
    final scores = <int>[];
    for (final s in overnights) {
      final sum = s.mergeKey == widget.session.mergeKey
          ? summary
          : await _repo.loadTruSleepSummary(s);
      final sc = sum?.sleepScore;
      if (sc != null && sc > 0) scores.add(sc);
    }
    if (!mounted) return;
    setState(() {
      _stages = stages;
      _summary = summary;
      _weekScoreAvg = meanOf(scores);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final session = widget.session;
    final overnight = sleepCrossesLocalMidnight(session);
    final end = sleepLocalFromUnix(session.endUnix);
    final arch = sleepArchitectureNote(_stages);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sleep',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.ink,
              ),
            ),
            Text(
              overnight ? 'Overnight · TruSleep' : 'Session · TruSleep',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  sleepFormatShortDate(end),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${sleepFormatWindow(session.beginUnix, session.endUnix)}'
                  '${overnight ? ' · overnight' : ''} · '
                  '${sleepFormatDuration(session.durationSec)}',
                  style: FathomTextStyles.mono(
                    fontSize: 12,
                    color: colors.inkFaint,
                  ),
                ),
                if (_summary != null) ...[
                  const SizedBox(height: 16),
                  _TruSleepSummarySection(
                    summary: _summary!,
                    weekScoreAvg: _weekScoreAvg,
                  ),
                  if (_summary!.isScientific) ...[
                    const SizedBox(height: 12),
                    _LandmarksSection(summary: _summary!),
                    const SizedBox(height: 12),
                    SleepContributors(
                      session: session,
                      summary: _summary!,
                      stages: _stages,
                    ),
                    const SizedBox(height: 12),
                    _AdvancedMetricsSection(summary: _summary!),
                  ],
                ],
                const SizedBox(height: 16),
                _StructureSection(stages: _stages),
                if (arch != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Architecture check',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.inkFaint,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            arch,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.inkDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const _HonestyFooter(),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text(
                      'Browse sleep history',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                    subtitle: Text(
                      'Other nights and naps this month',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.inkFaint,
                      ),
                    ),
                    trailing: Icon(Icons.chevron_right, color: colors.inkFaint),
                    onTap: () => SleepHistoryRoute.go(context),
                  ),
                ),
              ],
            ),
    );
  }
}

class _TruSleepSummarySection extends StatelessWidget {
  const _TruSleepSummarySection({
    required this.summary,
    this.weekScoreAvg,
  });

  final TruSleepSequenceSession summary;
  final double? weekScoreAvg;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final metrics = <(String, String)>[
      if (summary.avgHrv != null) ('HRV', '${summary.avgHrv}'),
      if (summary.avgHeartRate != null) ('HR', '${summary.avgHeartRate}'),
      if (summary.avgBreathRate != null) ('RR', '${summary.avgBreathRate}'),
      if (summary.avgOxygenSaturation != null)
        ('SpO₂', '${summary.avgOxygenSaturation}%'),
      if (summary.usableEfficiency != null)
        ('Eff', '${summary.usableEfficiency}%'),
    ];

    String? vsWeek;
    final score = summary.sleepScore;
    if (summary.isScientific && score != null && weekScoreAvg != null) {
      final d = (score - weekScoreAvg!).round();
      final sign = d >= 0 ? '+' : '';
      vsWeek = '7-day avg ${weekScoreAvg!.round()} · $sign$d';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              summary.isScientific ? 'TruSleep' : 'TruSleep · nap / stub',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (summary.sleepScore != null && summary.isScientific) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${summary.sleepScore}',
                    key: const ValueKey('sleep_score'),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.ink,
                    ),
                  ),
                  if (vsWeek != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          vsWeek,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.inkDim,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                'sleep score',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.inkFaint,
                ),
              ),
            ],
            if (!summary.isScientific) ...[
              const SizedBox(height: 8),
              Text(
                'No scientific score for this nap. Stages and duration still '
                'count toward the day.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.inkDim,
                ),
              ),
            ],
            if (metrics.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final m in metrics)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.$2,
                          style: FathomTextStyles.mono(
                            fontSize: 14,
                            color: colors.ink,
                          ),
                        ),
                        Text(
                          m.$1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LandmarksSection extends StatelessWidget {
  const _LandmarksSection({required this.summary});

  final TruSleepSequenceSession summary;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final points = <(String, int?)>[
      ('Bed', summary.bedTimeUnix),
      ('Asleep', summary.fallAsleepUnix),
      ('Wake', summary.wakeupUnix),
      ('Rise', summary.risingUnix),
    ].where((e) => e.$2 != null && e.$2! > 0).toList();

    if (points.isEmpty && summary.usableLatencySec == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Night landmarks',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (points.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final p in points)
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            sleepFormatHm(sleepLocalFromUnix(p.$2!)),
                            style: FathomTextStyles.mono(
                              fontSize: 13,
                              color: colors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.$1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.inkFaint,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            if (summary.usableLatencySec != null) ...[
              const SizedBox(height: 10),
              Text(
                'Latency ${sleepFormatDuration(summary.usableLatencySec!)}'
                '${summary.usableEfficiency != null ? ' · efficiency ${summary.usableEfficiency}%' : ''}',
                style: FathomTextStyles.mono(
                  fontSize: 11,
                  color: colors.inkDim,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdvancedMetricsSection extends StatelessWidget {
  const _AdvancedMetricsSection({required this.summary});

  final TruSleepSequenceSession summary;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final rows = <(String, String, String)>[
      if (summary.usableLatencySec != null)
        (
          'Sleep latency',
          sleepFormatDuration(summary.usableLatencySec!),
          'Bed → fall asleep',
        ),
      if (summary.usableDeepPart != null)
        (
          'Deep continuity',
          '${summary.usableDeepPart}',
          'Health Kit deep_sleep_part · not deep minutes',
        ),
      if (summary.usableEfficiency != null)
        (
          'Efficiency',
          '${summary.usableEfficiency}%',
          'Time asleep vs time in bed',
        ),
      if (summary.avgHrv != null)
        ('Sleep HRV', '${summary.avgHrv} ms', 'Overnight average'),
      if (summary.avgHeartRate != null)
        ('Sleep HR', '${summary.avgHeartRate} bpm', 'Overnight average'),
      if (summary.minHeartRate != null || summary.maxHeartRate != null)
        (
          'HR range',
          '${summary.minHeartRate ?? '—'}–${summary.maxHeartRate ?? '—'}',
          'Min–max when watch emits',
        ),
      if (summary.avgBreathRate != null)
        ('Respiratory rate', '${summary.avgBreathRate} /min', 'Overnight average'),
      if (summary.avgOxygenSaturation != null)
        ('SpO₂', '${summary.avgOxygenSaturation}%', 'Overnight average'),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

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
            const SizedBox(height: 4),
            Text(
              'From TruSleep SEQUENCE · watch-derived',
              style: FathomTextStyles.mono(
                fontSize: 11,
                color: colors.inkFaint,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 20, color: colors.line),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].$1,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rows[i].$3,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    rows[i].$2,
                    style: FathomTextStyles.mono(
                      fontSize: 14,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StructureSection extends StatelessWidget {
  const _StructureSection({required this.stages});

  final List<SleepStageSummary> stages;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    if (stages.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Stage structure',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.inkFaint,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No stage blocks for this session — not invented.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.inkDim,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Stage structure',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.inkFaint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SleepHypnogram(stages: stages),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Stage mix',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.inkFaint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SleepStageMixBars(stages: stages),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HonestyFooter extends StatelessWidget {
  const _HonestyFooter();

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Text(
      'No intra-night HR/HRV series · no movement or breathing-disturbance '
      'graphs on this companion path. Wearable stages ≠ PSG.',
      style: FathomTextStyles.mono(
        fontSize: 11,
        color: colors.inkFaint,
      ),
    );
  }
}
