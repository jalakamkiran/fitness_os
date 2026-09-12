import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/sleep_analytics.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';

/// Today hero: TruSleep score + duration + glance metrics.
class SleepTonightHero extends StatelessWidget {
  const SleepTonightHero({
    super.key,
    required this.session,
    this.summary,
    this.weekScoreAvg,
    this.onViewDetails,
  });

  final SleepSessionSummary session;
  final TruSleepSequenceSession? summary;
  final double? weekScoreAvg;
  final VoidCallback? onViewDetails;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final score = summary?.isScientific == true ? summary!.sleepScore : null;
    final mid = sleepMidSleepLocal(summary, session);
    final latency = summary?.usableLatencySec;
    final glance = <(String, String)>[
      if (summary?.usableEfficiency != null)
        ('Eff', '${summary!.usableEfficiency}%'),
      if (latency != null) ('Latency', sleepFormatDuration(latency)),
      if (summary?.usableDeepPart != null)
        ('Deep cont.', '${summary!.usableDeepPart}'),
      if (mid != null) ('Mid-sleep', sleepFormatHm(mid)),
    ];

    String? vsWeek;
    if (score != null && weekScoreAvg != null) {
      final delta = (score - weekScoreAvg!).round();
      final sign = delta >= 0 ? '+' : '';
      vsWeek =
          'vs 7-day avg ${weekScoreAvg!.round()} · $sign$delta';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Today · overnight',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (score != null) ...[
                        Text(
                          '$score',
                          key: const ValueKey('tonight_sleep_score'),
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                            height: 0.95,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'TruSleep score',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.inkDim,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (vsWeek != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            vsWeek,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.inkFaint,
                            ),
                          ),
                        ],
                      ] else ...[
                        Text(
                          sleepFormatDuration(session.durationSec),
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                          ),
                        ),
                        Text(
                          'asleep · TruSleep summary pending',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.inkFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (score != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        sleepFormatDuration(session.durationSec),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sleepFormatWindow(session.beginUnix, session.endUnix),
                        style: FathomTextStyles.mono(
                          fontSize: 11,
                          color: colors.inkFaint,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (glance.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: colors.line),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final g in glance)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.$2,
                            style: FathomTextStyles.mono(
                              fontSize: 13,
                              color: colors.ink,
                            ),
                          ),
                          Text(
                            g.$1,
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
            if (onViewDetails != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onViewDetails,
                  child: const Text('View night details'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
