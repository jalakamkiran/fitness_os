import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_stage_mix.dart';

/// Shared calm sleep session card (list today / history rows).
class SleepSessionCard extends StatelessWidget {
  const SleepSessionCard({
    super.key,
    required this.session,
    this.stages = const [],
    this.kicker,
    this.sleepScore,
    this.showDetailsCta = false,
    this.onViewDetails,
    this.compact = false,
  });

  final SleepSessionSummary session;
  final List<SleepStageSummary> stages;
  final String? kicker;
  /// TruSleep score when known (scientific overnight only).
  final int? sleepScore;
  final bool showDetailsCta;
  final VoidCallback? onViewDetails;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final end = sleepLocalFromUnix(session.endUnix);
    final overnight = sleepCrossesLocalMidnight(session);
    final window = sleepFormatWindow(session.beginUnix, session.endUnix);
    final duration = sleepFormatDuration(session.durationSec);
    final kind = overnight ? 'overnight' : 'nap';
    final showScore = sleepScore != null && sleepScore! > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kicker != null) ...[
              Text(
                kicker!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.inkFaint,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sleepFormatShortDate(end),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.inkDim,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        duration,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showScore)
                  Text(
                    '$sleepScore',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.ink,
                    ),
                  )
                else if (compact && !overnight)
                  Text(
                    'nap',
                    style: FathomTextStyles.mono(
                      fontSize: 12,
                      color: colors.inkFaint,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$window · $kind',
              style: FathomTextStyles.mono(
                fontSize: 12,
                color: colors.inkFaint,
              ),
            ),
            if (stages.isNotEmpty) ...[
              const SizedBox(height: 12),
              SleepStageChips(stages: stages),
            ],
            if (showDetailsCta && onViewDetails != null && !compact) ...[
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onViewDetails,
                child: const Text('View more details'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
