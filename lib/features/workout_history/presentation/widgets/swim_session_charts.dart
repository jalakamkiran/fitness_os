import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
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

/// Athlete chart series (pace-first progressive disclosure).
enum SwimChartSeries { pace, swolf, strokes, overlay, hr }

/// Interval charts for a swim session — pace default, other series via chips.
///
/// Null / non-positive pace is never plotted as 0 (gap/skip). Caller should
/// pass invent-guard–filtered laps (same set as the intervals table).
/// Locked in-session HR (when present) is a series chip — not a sibling card.
class SwimSessionCharts extends StatefulWidget {
  const SwimSessionCharts({
    super.key,
    required this.laps,
    this.hrPoints = const [],
    this.initialSeries = SwimChartSeries.pace,
    this.onSeriesChanged,
    this.scrollKey,
    this.showExpand = true,
    this.onExpand,
  });

  final List<SwimLapMetrics> laps;

  /// Locked in-session HR samples (≥2 points → HR chip available).
  final List<RunStreamPoint> hrPoints;

  final SwimChartSeries initialSeries;
  final ValueChanged<SwimChartSeries>? onSeriesChanged;

  /// Anchor for jump-link scroll restore.
  final Key? scrollKey;

  /// When false, hide landscape expand CTA (e.g. already expanded).
  final bool showExpand;

  /// Opens landscape analysis; returns last series when dismissed.
  final Future<SwimChartSeries?> Function(SwimChartSeries current)? onExpand;

  @override
  State<SwimSessionCharts> createState() => _SwimSessionChartsState();
}

class _SwimSessionChartsState extends State<SwimSessionCharts> {
  late SwimChartSeries _series;

  @override
  void initState() {
    super.initState();
    _series = widget.initialSeries;
  }

  @override
  void didUpdateWidget(covariant SwimSessionCharts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSeries != widget.initialSeries) {
      _series = widget.initialSeries;
    }
  }

  void _select(SwimChartSeries s) {
    setState(() => _series = s);
    widget.onSeriesChanged?.call(s);
  }

  Future<void> _expand() async {
    final expand = widget.onExpand;
    if (expand == null) return;
    final result = await expand(_series);
    if (!mounted || result == null) return;
    _select(result);
  }

  @override
  Widget build(BuildContext context) {
    final ordered = [...widget.laps]..sort((a, b) => a.index.compareTo(b.index));
    final paces = ordered.map((l) => l.paceSecPer100m).toList();
    final swolfs = ordered.map((l) => l.swolf).toList();
    final strokes = ordered.map((l) => l.strokes).toList();
    final hrOnly = [
      for (final p in widget.hrPoints)
        if (p.hrBpm != null) p,
    ];
    final hasPace = paces.any((v) => v != null && v > 0);
    final hasSwolf = swolfs.any((v) => v != null && v > 0);
    final hasStrokes = strokes.any((v) => v != null && v > 0);
    final hasHr = hrOnly.length >= 2;
    if (!hasPace && !hasSwolf && !hasStrokes && !hasHr) {
      return const SizedBox.shrink();
    }

    final available = <SwimChartSeries>[
      if (hasPace) SwimChartSeries.pace,
      if (hasSwolf) SwimChartSeries.swolf,
      if (hasStrokes) SwimChartSeries.strokes,
      if (hasPace && hasSwolf) SwimChartSeries.overlay,
      if (hasHr) SwimChartSeries.hr,
    ];
    if (!available.contains(_series)) {
      _series = available.first;
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = SwimChartColors.accent(context);
    final labels = [
      for (var i = 0; i < ordered.length; i++) 'I${i + 1}',
    ];
    final dense = ordered.length >= 10 || hrOnly.length >= 40;
    final tickStep = ordered.isEmpty
        ? 1
        : (dense ? math.max(1, (ordered.length / 6).ceil()) : 1);
    final caption = ordered.isNotEmpty
        ? '${ordered.length} intervals${hasHr ? ' · HR locked' : ''}'
        : 'HR · in-session samples';

    return Card(
      key: widget.scrollKey,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Charts',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.showExpand && widget.onExpand != null)
                  TextButton.icon(
                    key: const Key('swim-chart-expand'),
                    onPressed: _expand,
                    icon: const Icon(Icons.open_in_full, size: 16),
                    label: Text(
                      'Expand',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: dense ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in available)
                  ChoiceChip(
                    key: Key('swim-series-${s.name}'),
                    label: Text(_seriesLabel(s)),
                    selected: _series == s,
                    onSelected: (_) => _select(s),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ChartBlock(
              title: _seriesTitle(_series),
              caption: _seriesCaption(_series),
              child: switch (_series) {
                SwimChartSeries.pace => _IntervalBarChart(
                    values: paces,
                    color: accent,
                    labels: labels,
                    progressiveHot: true,
                    tickStep: tickStep,
                    gapNull: true,
                  ),
                SwimChartSeries.swolf => _IntervalLineChart(
                    values: swolfs,
                    color: accent,
                    fill: true,
                    labels: labels,
                    hotTail: true,
                    tickStep: tickStep,
                  ),
                SwimChartSeries.strokes => _IntervalBarChart(
                    values: strokes,
                    color: SwimChartColors.hot,
                    labels: labels,
                    tickStep: tickStep,
                    gapNull: true,
                  ),
                SwimChartSeries.overlay => _PaceSwolfOverlay(
                    paces: paces,
                    swolfs: swolfs,
                    paceColor: SwimChartColors.hot,
                    swolfColor: SwimChartColors.amber,
                    labels: labels,
                    tickStep: tickStep,
                  ),
                SwimChartSeries.hr => _HrStreamChart(points: hrOnly),
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _seriesLabel(SwimChartSeries s) => switch (s) {
        SwimChartSeries.pace => 'Pace',
        SwimChartSeries.swolf => 'SWOLF',
        SwimChartSeries.strokes => 'Strokes',
        SwimChartSeries.overlay => 'Overlay',
        SwimChartSeries.hr => 'HR',
      };

  static String _seriesTitle(SwimChartSeries s) => switch (s) {
        SwimChartSeries.pace => 'Pace by interval',
        SwimChartSeries.swolf => 'SWOLF',
        SwimChartSeries.strokes => 'Strokes per length',
        SwimChartSeries.overlay => 'Pace + SWOLF',
        SwimChartSeries.hr => 'Heart rate',
      };

  static String _seriesCaption(SwimChartSeries s) => switch (s) {
        SwimChartSeries.pace => 's/100m · higher = slower',
        SwimChartSeries.swolf => 'time + strokes · lower better',
        SwimChartSeries.strokes => 'count · spike = churn',
        SwimChartSeries.overlay => '0–1 normalized · ↑ = worse',
        SwimChartSeries.hr => 'bpm · in-session samples',
      };
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
        SizedBox(height: 160, child: child),
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
    this.tickStep = 1,
    this.gapNull = false,
  });

  final List<int?> values;
  final Color color;
  final List<String> labels;
  final bool progressiveHot;
  final int tickStep;

  /// When true, null/non-positive values are omitted (not plotted as 0).
  final bool gapNull;

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
      final v = values[i];
      if (v == null || v <= 0) {
        return Colors.transparent;
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
                if (tickStep > 1 && i % tickStep != 0 && i != labels.length - 1) {
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
            if (!(gapNull && (values[i] == null || values[i]! <= 0)))
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i]!.toDouble(),
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
    this.tickStep = 1,
  });

  final List<int?> values;
  final Color color;
  final List<String> labels;
  final bool fill;
  final bool hotTail;
  final int tickStep;

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
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length || v != i.toDouble()) {
                  return const SizedBox.shrink();
                }
                if (tickStep > 1 && i % tickStep != 0 && i != labels.length - 1) {
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
    this.tickStep = 1,
  });

  final List<int?> paces;
  final List<int?> swolfs;
  final Color paceColor;
  final Color swolfColor;
  final List<String> labels;
  final int tickStep;

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
                      if (tickStep > 1 &&
                          i % tickStep != 0 &&
                          i != labels.length - 1) {
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

/// Locked in-session HR as a time-series line (offsetSec → bpm).
class _HrStreamChart extends StatelessWidget {
  const _HrStreamChart({required this.points});

  final List<RunStreamPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    for (final p in points) {
      final hr = p.hrBpm;
      if (hr == null || hr <= 0) continue;
      spots.add(FlSpot(p.offsetSec.toDouble(), hr.toDouble()));
    }
    if (spots.length < 2) return const SizedBox.shrink();

    final ys = spots.map((s) => s.y).toList();
    final maxY = ys.reduce(math.max);
    final minY = ys.reduce(math.min);
    final pad = math.max(2.0, (maxY - minY) * 0.12);
    final top = maxY + pad;
    final bottom = math.max(0.0, minY - pad);
    final maxX = spots.last.x;
    final tickEvery = math.max(1.0, maxX / 4);

    return LineChart(
      LineChartData(
        minX: spots.first.x,
        maxX: maxX,
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
              interval: tickEvery,
              getTitlesWidget: (v, _) {
                final m = (v / 60).floor();
                final s = (v % 60).round();
                return Text(
                  '$m:${s.toString().padLeft(2, '0')}',
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
            color: SwimChartColors.hot,
            barWidth: 1.75,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: SwimChartColors.hot.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

double _barWidth(int count) {
  if (count <= 4) return 10;
  if (count <= 8) return 7;
  if (count <= 14) return 5;
  return 3.5;
}
