import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/vitals/domain/sleep_analytics.dart';

/// Oura-style vertical sleep timing bars (midnight→noon axis).
class SleepTimingChart extends StatelessWidget {
  const SleepTimingChart({super.key, required this.days});

  final List<SleepTimingDay> days;

  static const _weekday = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    if (days.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sleep timing · 7 nights',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 32,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final t in ['00:00', '03:00', '06:00', '09:00', '12:00'])
                          Text(
                            t,
                            style: FathomTextStyles.mono(
                              fontSize: 9,
                              color: colors.inkFaint,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final day in days)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _DayRail(day: day),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _weekday[day.endDay.weekday - 1],
                                    style: FathomTextStyles.mono(
                                      fontSize: 9,
                                      color: day.isToday
                                          ? colors.accent
                                          : colors.inkFaint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _Leg(
                  color: colors.accent.withValues(alpha: 0.25),
                  label: 'Time in bed',
                ),
                _Leg(color: colors.accent, label: 'Asleep'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayRail extends StatelessWidget {
  const _DayRail({required this.day});

  final SleepTimingDay day;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    if (!day.hasData) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.line.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    final bed = day.bedFrac.clamp(0.0, 1.0);
    final rise = day.riseFrac.clamp(0.0, 1.0);
    final asleep = day.asleepFrac.clamp(0.0, 1.0);
    final wake = day.wakeFrac.clamp(0.0, 1.0);
    final tibTop = bed;
    final tibH = (rise - bed).clamp(0.02, 1.0);
    final asleepTop = asleep;
    final asleepH = (wake - asleep).clamp(0.02, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.line.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              Positioned(
                top: h * tibTop,
                left: constraints.maxWidth * 0.18,
                right: constraints.maxWidth * 0.18,
                height: h * tibH,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              Positioned(
                top: h * asleepTop,
                left: constraints.maxWidth * 0.22,
                right: constraints.maxWidth * 0.22,
                height: h * asleepH,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(5),
                    border: day.isToday
                        ? Border.all(
                            color: colors.accent.withValues(alpha: 0.5),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.inkDim,
              ),
        ),
      ],
    );
  }
}
