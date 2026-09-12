import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/sleep_analytics.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';

/// Oura-style contributor chips explaining the night (no second opaque score).
class SleepContributors extends StatelessWidget {
  const SleepContributors({
    super.key,
    required this.session,
    required this.summary,
    required this.stages,
  });

  final SleepSessionSummary session;
  final TruSleepSequenceSession summary;
  final List<SleepStageSummary> stages;

  @override
  Widget build(BuildContext context) {
    if (!summary.isScientific) return const SizedBox.shrink();
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final mins = stageMinutesOf(stages);
    final deepShare = mins.share(mins.deep);
    final mid = sleepMidSleepLocal(summary, session);
    final midHour = mid?.hour;

    final items = <_Item>[
      _Item(
        name: 'Duration',
        value: sleepFormatDuration(session.durationSec),
        fill: (session.durationSec / (8 * 3600)).clamp(0.0, 1.0),
        question: 'Enough total sleep?',
      ),
      if (summary.usableEfficiency != null)
        _Item(
          name: 'Efficiency',
          value: '${summary.usableEfficiency}%',
          fill: summary.usableEfficiency! / 100,
          question: 'Time in bed spent asleep?',
        ),
      if (summary.usableLatencySec != null)
        _Item(
          name: 'Latency',
          value: sleepFormatDuration(summary.usableLatencySec!),
          fill: (1 - (summary.usableLatencySec! / (45 * 60))).clamp(0.15, 1.0),
          question: 'Fell asleep quickly?',
        ),
      if (summary.usableDeepPart != null)
        _Item(
          name: 'Deep cont.',
          value: '${summary.usableDeepPart}',
          fill: summary.usableDeepPart! / 100,
          question: 'Deep continuity · not minutes',
        ),
      if (deepShare != null && mins.deep > 0)
        _Item(
          name: 'Deep share',
          value: '${(deepShare * 100).round()}%',
          fill: (deepShare / 0.25).clamp(0.0, 1.0),
          question: '${mins.deep}m deep · structure',
        ),
      if (midHour != null)
        _Item(
          name: 'Timing',
          value: midHour >= 0 && midHour < 3 ? 'On track' : 'Late',
          fill: midHour >= 0 && midHour < 3 ? 0.85 : 0.42,
          warn: !(midHour >= 0 && midHour < 3),
          question: mid == null
              ? 'Mid-sleep timing'
              : 'Mid-sleep ${sleepFormatHm(mid)}',
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What drove the night · contributors',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final w = (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: w,
                        child: _Chip(item: item),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Item {
  const _Item({
    required this.name,
    required this.value,
    required this.fill,
    required this.question,
    this.warn = false,
  });

  final String name;
  final String value;
  final double fill;
  final String question;
  final bool warn;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final barColor = item.warn ? colors.amber : colors.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.inkDim,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                item.value,
                style: FathomTextStyles.mono(
                  fontSize: 13,
                  color: colors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: item.fill.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: colors.line,
              color: barColor,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            item.question,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.inkFaint,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
