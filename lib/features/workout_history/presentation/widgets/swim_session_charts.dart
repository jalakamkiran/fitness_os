import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';

/// Fathom accent tokens — prefer Theme primary when it is already mint-like;
/// otherwise use locked swim chart accents.
abstract final class SwimChartColors {
  static const mint = Color(0xFF19B7B0);
  static const mintDark = Color(0xFF5DFFC4);
  static const amber = Color(0xFFD97706);
  static const hot = Color(0xFFE85D4C);

  static Color accent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    // Blueprint primary is B/W — use Fathom mint for swim charts.
    if (scheme.primary == Colors.black || scheme.primary == Colors.white) {
      return brightness == Brightness.dark ? mintDark : mint;
    }
    return scheme.primary;
  }
}

/// Interval charts for a swim session — Pace → SWOLF → Strokes → Overlay.
///
/// Hidden when [laps] is empty or no chartable series. HR chart only when
/// [hrCoverage] is [SwimHrCoverage.present]; otherwise a locked empty note.
/// Caller should pass invent-guard–filtered laps (same set as the intervals table).
class SwimSessionCharts extends StatelessWidget {
  const SwimSessionCharts({
    super.key,
    required this.laps,
    this.hrCoverage = SwimHrCoverage.absent,
  });

  final List<SwimLapMetrics> laps;
  final SwimHrCoverage hrCoverage;

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) return const SizedBox.shrink();

    final ordered = [...laps]..sort((a, b) => a.index.compareTo(b.index));
    final paces = ordered.map((l) => l.paceSecPer100m).toList();
    final swolfs = ordered.map((l) => l.swolf).toList();
    final strokes = ordered.map((l) => l.strokes).toList();
    final hasPace = paces.any((v) => v != null && v > 0);
    final hasSwolf = swolfs.any((v) => v != null && v > 0);
    final hasStrokes = strokes.any((v) => v != null && v > 0);
    if (!hasPace && !hasSwolf && !hasStrokes) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = SwimChartColors.accent(context);
    final labels = [
      for (var i = 0; i < ordered.length; i++) 'I${i + 1}',
    ];
    final showHrChart = hrCoverage == SwimHrCoverage.present;

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
            '${ordered.length} intervals · synced to table',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: [
            // Locked order: Pace → SWOLF → Strokes → normalized overlay.
            if (hasPace) ...[
              _ChartBlock(
                title: 'Pace by interval',
                caption: 's/100m · higher = slower',
                child: _IntervalBarChart(
                  values: paces,
                  color: accent,
                  labels: labels,
                  progressiveHot: true,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (hasSwolf) ...[
              _ChartBlock(
                title: 'SWOLF',
                caption: 'time + strokes · lower better',
                child: _IntervalLineChart(
                  values: swolfs,
                  color: accent,
                  fill: true,
                  labels: labels,
                  hotTail: true,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (hasStrokes) ...[
              _ChartBlock(
                title: 'Strokes per length',
                caption: 'count · spike = churn',
                child: _IntervalBarChart(
                  values: strokes,
                  color: SwimChartColors.hot,
                  labels: labels,
                ),
              ),
              if (hasPace && hasSwolf) const SizedBox(height: 16),
            ],
            if (hasPace && hasSwolf) ...[
              _ChartBlock(
                title: 'Pace + SWOLF',
                caption: '0–1 normalized · ↑ = worse',
                child: _PaceSwolfOverlay(
                  paces: paces,
                  swolfs: swolfs,
                  paceColor: SwimChartColors.hot,
                  swolfColor: SwimChartColors.amber,
                  labels: labels,
                ),
              ),
            ],
            if (!showHrChart) ...[
              const SizedBox(height: 12),
              Text(
                'Heart rate — hidden (no sample stream on this session)',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
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

class _IntervalBarChart extends StatelessWidget {
  const _IntervalBarChart({
    required this.values,
    required this.color,
    required this.labels,
    this.progressiveHot = false,
  });

  final List<int?> values;
  final Color color;
  final List<String> labels;

  /// When true, late intervals shift accent → amber → hot (locked pace chart).
  final bool progressiveHot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final present = values.whereType<int>().where((v) => v > 0).toList();
    if (present.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxY = present.reduce(math.max).toDouble();
    final minY = present.reduce(math.min).toDouble();
    final top = maxY * 1.12;
    final bottom = math.max(0.0, minY * 0.85);
    final n = values.length;
    final hotFrom = (n * 0.75).floor();
    final amberFrom = (n * 0.55).floor();

    Color rodColor(int i) {
      if (values[i] == null || values[i]! <= 0) {
        return scheme.outlineVariant.withValues(alpha: 0.35);
      }
      if (!progressiveHot) return color.withValues(alpha: 0.85);
      if (i >= hotFrom) return SwimChartColors.hot.withValues(alpha: 0.9);
      if (i >= amberFrom) return SwimChartColors.amber.withValues(alpha: 0.88);
      return color.withValues(alpha: 0.85);
    }

    return BarChart(
      BarChartData(
        minY: bottom == top ? 0 : bottom,
        maxY: top <= 0 ? 1 : top,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: const BarTouchData(enabled: true),
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
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 9,
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: math.max(1, (top - bottom) / 3),
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 0.6,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (values[i] ?? 0).toDouble(),
                  color: rodColor(i),
                  width: _barWidth(values.length),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _IntervalLineChart extends StatelessWidget {
  const _IntervalLineChart({
    required this.values,
    required this.color,
    required this.labels,
    this.fill = false,
    this.hotTail = false,
  });

  final List<int?> values;
  final Color color;
  final List<String> labels;
  final bool fill;

  /// Last two points use hot accent (locked SWOLF chart).
  final bool hotTail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v != null && v > 0) {
        spots.add(FlSpot(i.toDouble(), v.toDouble()));
      }
    }
    if (spots.isEmpty) return const SizedBox.shrink();

    final ys = spots.map((s) => s.y).toList();
    final maxY = ys.reduce(math.max);
    final minY = ys.reduce(math.min);
    final pad = math.max(2.0, (maxY - minY) * 0.12);
    final top = maxY + pad;
    final bottom = math.max(0.0, minY - pad);
    final lastX = spots.last.x;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(0, values.length - 1).toDouble(),
        minY: bottom == top ? 0 : bottom,
        maxY: top <= 0 ? 1 : top,
        lineTouchData: const LineTouchData(enabled: true),
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
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length || v != i.toDouble()) {
                  return const SizedBox.shrink();
                }
                return Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 9,
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
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
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 0.6,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 1.75,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) {
                final nearTail = hotTail && spot.x >= lastX - 1;
                final c = nearTail ? SwimChartColors.hot : color;
                return FlDotCirclePainter(
                  radius: 2.2,
                  color: c,
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: fill,
              color: color.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dual series on a shared 0–1 normalized Y so pace and SWOLF share a canvas.
class _PaceSwolfOverlay extends StatelessWidget {
  const _PaceSwolfOverlay({
    required this.paces,
    required this.swolfs,
    required this.paceColor,
    required this.swolfColor,
    required this.labels,
  });

  final List<int?> paces;
  final List<int?> swolfs;
  final Color paceColor;
  final Color swolfColor;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = math.min(paces.length, swolfs.length);
    final paceSpots = <FlSpot>[];
    final swolfSpots = <FlSpot>[];

    final paceVals =
        paces.take(n).whereType<int>().where((v) => v > 0).toList();
    final swolfVals =
        swolfs.take(n).whereType<int>().where((v) => v > 0).toList();
    if (paceVals.isEmpty || swolfVals.isEmpty) {
      return const SizedBox.shrink();
    }

    final pMin = paceVals.reduce(math.min).toDouble();
    final pMax = paceVals.reduce(math.max).toDouble();
    final sMin = swolfVals.reduce(math.min).toDouble();
    final sMax = swolfVals.reduce(math.max).toDouble();

    double norm(int? v, double min, double max) {
      if (v == null || v <= 0) return double.nan;
      if (max <= min) return 0.5;
      return (v - min) / (max - min);
    }

    for (var i = 0; i < n; i++) {
      final pn = norm(paces[i], pMin, pMax);
      final sn = norm(swolfs[i], sMin, sMax);
      if (!pn.isNaN) paceSpots.add(FlSpot(i.toDouble(), pn));
      if (!sn.isNaN) swolfSpots.add(FlSpot(i.toDouble(), sn));
    }

    return Column(
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(0, n - 1).toDouble(),
              minY: -0.05,
              maxY: 1.05,
              lineTouchData: const LineTouchData(enabled: true),
              titlesData: FlTitlesData(
                topTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 14,
                    getTitlesWidget: (v, meta) {
                      if (v != meta.max) return const SizedBox.shrink();
                      return Text(
                        'worse ↑',
                        style: TextStyle(
                          fontSize: 8,
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                  ),
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
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= labels.length || v != i.toDouble()) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 9,
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
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
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                  strokeWidth: 0.6,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: paceSpots,
                  isCurved: false,
                  color: paceColor,
                  barWidth: 1.6,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                      radius: 2,
                      color: paceColor,
                      strokeWidth: 0,
                    ),
                  ),
                ),
                LineChartBarData(
                  spots: swolfSpots,
                  isCurved: false,
                  color: swolfColor,
                  barWidth: 1.6,
                  isStrokeCapRound: true,
                  dashArray: const [4, 3],
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                      radius: 2,
                      color: swolfColor,
                      strokeWidth: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _LegendDot(color: paceColor, label: 'pace (↑=slower)'),
            const SizedBox(width: 12),
            _LegendDot(color: swolfColor, label: 'swolf'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

double _barWidth(int count) {
  if (count <= 4) return 10;
  if (count <= 8) return 7;
  if (count <= 14) return 5;
  return 3.5;
}
