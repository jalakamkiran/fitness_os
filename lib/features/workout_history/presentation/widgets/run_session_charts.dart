import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';

/// Pace then HR charts — only when decoded [RunStreamPoint] series exist.
///
/// Opaque side-file bytes or empty points → [SizedBox.shrink] (unobserved),
/// never empty zero series (AE2 / AE9 honesty).
class RunSessionCharts extends StatelessWidget {
  const RunSessionCharts({super.key, required this.points});

  final List<RunStreamPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final pace = points.map((p) => p.paceSecPerKm).toList();
    final hrs = points.map((p) => p.hrBpm?.toDouble()).toList();
    final hasPace = pace.any((v) => v != null && v > 0);
    final hasHr = hrs.any((v) => v != null && v > 0);
    if (!hasPace && !hasHr) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = SwimChartColors.accent(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text(
            'Session charts',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'This run · fetched streams only',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: [
            // Locked order: Pace → HR.
            if (hasPace) ...[
              _ChartBlock(
                title: 'Pace',
                caption: 's/km · higher = slower',
                child: _RunLineChart(
                  values: pace,
                  color: accent,
                  offsets: points.map((p) => p.offsetSec).toList(),
                ),
              ),
              if (hasHr) const SizedBox(height: 16),
            ],
            if (hasHr)
              _ChartBlock(
                title: 'Heart rate',
                caption: 'bpm · in-run samples',
                child: _RunLineChart(
                  values: hrs,
                  color: SwimChartColors.hot,
                  offsets: points.map((p) => p.offsetSec).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChartBlock extends StatelessWidget {
  const _ChartBlock({
    required this.title,
    required this.caption,
    required this.child,
  });

  final String title;
  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: theme.textTheme.labelSmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 132, child: child),
      ],
    );
  }
}

class _RunLineChart extends StatelessWidget {
  const _RunLineChart({
    required this.values,
    required this.color,
    required this.offsets,
  });

  final List<double?> values;
  final Color color;
  final List<int> offsets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null || v <= 0) continue;
      final x = offsets.isNotEmpty ? offsets[i].toDouble() : i.toDouble();
      spots.add(FlSpot(x, v));
    }
    if (spots.length < 2) return const SizedBox.shrink();

    final ys = spots.map((s) => s.y).toList();
    final maxY = ys.reduce(math.max);
    final minY = ys.reduce(math.min);
    final top = maxY * 1.12;
    final bottom = math.max(0.0, minY * 0.85);

    return LineChart(
      LineChartData(
        minY: bottom == top ? 0 : bottom,
        maxY: top <= 0 ? 1 : top,
        lineTouchData: const LineTouchData(enabled: true),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                v.round().toString(),
                style: TextStyle(
                  fontSize: 9,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
