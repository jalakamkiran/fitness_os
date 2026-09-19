import 'dart:math' as math;

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';

/// Pace / HR / cadence charts — only when decoded [RunStreamPoint] series exist.
///
/// Opaque side-file bytes or empty points → [SizedBox.shrink] (unobserved),
/// never empty zero series (AE2 / AE9 honesty).
class RunSessionCharts extends StatefulWidget {
  const RunSessionCharts({
    super.key,
    required this.points,
    this.title = 'Session charts',
    this.caption = 'This run · fetched streams only',
    this.hrCaption = 'bpm · in-run samples',
    this.showStoryTabs = false,
    this.showProbeNote = false,
  });

  final List<RunStreamPoint> points;
  final String title;
  final String caption;

  /// Inner HR-block caption. Swim/strength hosts pass in-session wording.
  final String hrCaption;

  /// Product story filter chips (All / Pace / HR / Cadence).
  final bool showStoryTabs;

  /// Fetch-probe disclaimer (omitted on product surface).
  final bool showProbeNote;

  @override
  State<RunSessionCharts> createState() => _RunSessionChartsState();
}

enum _StoryFocus { all, pace, hr, cadence }

class _RunSessionChartsState extends State<RunSessionCharts> {
  _StoryFocus _focus = _StoryFocus.all;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) return const SizedBox.shrink();

    final pace = points.map((p) => p.paceSecPerKm).toList();
    final hrs = points.map((p) => p.hrBpm?.toDouble()).toList();
    final cads = points.map((p) => p.cadenceSpm?.toDouble()).toList();
    final hasPace = pace.any((v) => v != null && v > 0);
    final hasHr = hrs.any((v) => v != null && v > 0);
    final hasCadence = cads.any((v) => v != null && v > 0);
    if (!hasPace && !hasHr && !hasCadence) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = FathomColors.of(context);
    final accent = SwimChartColors.accent(context);
    final offsets = points.map((p) => p.offsetSec).toList();

    final showPace = hasPace &&
        (_focus == _StoryFocus.all || _focus == _StoryFocus.pace);
    final showHr =
        hasHr && (_focus == _StoryFocus.all || _focus == _StoryFocus.hr);
    final showCad = hasCadence &&
        (_focus == _StoryFocus.all || _focus == _StoryFocus.cadence);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ),
              Text(
                widget.caption,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'IBM Plex Mono',
                  color: colors.inkFaint,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (widget.showStoryTabs) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final tabs = <(_StoryFocus, String)>[
                  (_StoryFocus.all, 'All'),
                  if (hasPace) (_StoryFocus.pace, 'Pace'),
                  if (hasHr) (_StoryFocus.hr, 'HR'),
                  if (hasCadence) (_StoryFocus.cadence, 'Cadence'),
                ];
                return Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: _StoryTab(
                          label: tabs[i].$2,
                          selected: _focus == tabs[i].$1,
                          onTap: () => setState(() => _focus = tabs[i].$1),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          if (showPace) ...[
            _ChartBlock(
              title: 'Pace',
              caption: 's/km · from watch splits (step)',
              child: _RunLineChart(
                values: pace,
                color: accent,
                offsets: offsets,
              ),
            ),
            if (showCad || showHr) const SizedBox(height: 16),
          ],
          if (showCad) ...[
            _ChartBlock(
              title: 'Cadence',
              caption: 'spm · sample byte3 (shape may differ from watch)',
              child: _RunLineChart(
                values: cads,
                color: colors.amber,
                offsets: offsets,
              ),
            ),
            if (showHr) const SizedBox(height: 16),
          ],
          if (showHr)
            _ChartBlock(
              title: 'Heart rate',
              caption: widget.hrCaption,
              child: _RunLineChart(
                values: hrs,
                color: SwimChartColors.hot,
                offsets: offsets,
              ),
            ),
          if (widget.showProbeNote) ...[
            const SizedBox(height: 12),
            Text(
              'Time-series GCT / VO / balance / altitude omitted until the '
              'sample bitmap carries them. Scalars come from Totals leftovers.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.inkFaint,
                fontSize: 11,
              ),
            ),
          ] else if (widget.showStoryTabs) ...[
            const SizedBox(height: 8),
            Text(
              'Pace from locked km splits · invent-guard on sample pace',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.inkFaint,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StoryTab extends StatelessWidget {
  const _StoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Material(
      color: selected
          ? Color.lerp(colors.bgElev, colors.accent, 0.16)
          : colors.bg,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? Color.lerp(colors.line, colors.accent, 0.4)!
              : colors.line,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: selected ? colors.ink : colors.inkDim,
                ),
          ),
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
    final colors = FathomColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: theme.textTheme.labelSmall?.copyWith(
            fontFamily: 'IBM Plex Mono',
            color: colors.inkFaint,
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
    final colors = FathomColors.of(context);
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
            color: colors.line.withValues(alpha: 0.7),
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
                  color: colors.inkFaint,
                  fontFamily: 'IBM Plex Mono',
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
