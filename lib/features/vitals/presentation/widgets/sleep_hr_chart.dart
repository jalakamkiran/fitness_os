import 'dart:math' as math;

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/sleep_hr_window.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';

/// Continuous HR min/avg/max + BPM line for a sleep window.
class SleepHrChart extends StatelessWidget {
  const SleepHrChart({
    super.key,
    required this.samples,
    this.overnightCaption = false,
  });

  final List<DailyHrSample> samples;
  final bool overnightCaption;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final stats = sleepHrStats(samples);
    if (stats == null || samples.length < 2) {
      return const SizedBox.shrink();
    }

    final spots = <FlSpot>[];
    final t0 = samples.first.timestampUnix;
    for (final s in samples) {
      spots.add(
        FlSpot(
          (s.timestampUnix - t0).toDouble(),
          s.bpm.toDouble(),
        ),
      );
    }
    final ys = spots.map((s) => s.y).toList();
    final maxY = ys.reduce(math.max);
    final minY = ys.reduce(math.min);
    final pad = math.max(2.0, (maxY - minY) * 0.12);
    final top = maxY + pad;
    final bottom = math.max(0.0, minY - pad);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(label: 'Min', value: '${stats.minBpm}'),
            ),
            Expanded(
              child: _Metric(label: 'Avg', value: '${stats.avgBpm}'),
            ),
            Expanded(
              child: _Metric(label: 'Max', value: '${stats.maxBpm}'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minX: spots.first.x,
              maxX: spots.last.x,
              minY: bottom == top ? 0 : bottom,
              maxY: top <= 0 ? 1 : top,
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 18,
                    getTitlesWidget: (v, meta) {
                      if (v != meta.min && v != meta.max) {
                        return const SizedBox.shrink();
                      }
                      final unix = t0 + v.round();
                      return Text(
                        sleepFormatHm(sleepLocalFromUnix(unix)),
                        style: FathomTextStyles.mono(
                          fontSize: 10,
                          color: colors.inkFaint,
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: colors.line.withValues(alpha: 0.6),
                  strokeWidth: 0.6,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: colors.accent,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: colors.accent.withValues(alpha: 0.18),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (overnightCaption) ...[
          const SizedBox(height: 8),
          Text(
            'window crossed midnight · both dayKeys',
            style: FathomTextStyles.mono(
              fontSize: 11,
              color: colors.inkFaint,
            ),
          ),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
              ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.ink,
                    ),
              ),
              TextSpan(
                text: ' bpm',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.inkFaint,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
