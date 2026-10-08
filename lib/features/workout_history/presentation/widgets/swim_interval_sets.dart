import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_stroke_icon.dart';

/// Warmup / Main / Cool (or Block N) grouping for athlete intervals.
class SwimIntervalSet {
  const SwimIntervalSet({
    required this.id,
    required this.label,
    required this.kind,
    required this.effort,
    required this.laps,
  });

  final String id;
  final String label;
  final SwimSetKind kind;
  final String effort;
  final List<SwimLapMetrics> laps;
}

enum SwimSetKind { warmup, main, cool, block }

/// Group invent-guarded (or dig-deeper) laps into collapsible sets.
///
/// Matches the coach-detail design: ≤4 → one main; ≤24 → warmup/main/cool;
/// denser → four equal-ish blocks.
List<SwimIntervalSet> buildSwimIntervalSets(List<SwimLapMetrics> laps) {
  final ordered = [...laps]..sort((a, b) => a.index.compareTo(b.index));
  final n = ordered.length;
  if (n == 0) return const [];
  if (n <= 4) {
    return [
      SwimIntervalSet(
        id: 'main',
        label: 'Main set',
        kind: SwimSetKind.main,
        effort: 'Steady',
        laps: ordered,
      ),
    ];
  }
  if (n <= 24) {
    final w = math.max(2, (n * 0.2).floor());
    final c = math.max(2, (n * 0.15).floor());
    final m = n - w - c;
    return [
      SwimIntervalSet(
        id: 'warmup',
        label: 'Warmup',
        kind: SwimSetKind.warmup,
        effort: 'Easy',
        laps: ordered.sublist(0, w),
      ),
      SwimIntervalSet(
        id: 'main',
        label: 'Main set',
        kind: SwimSetKind.main,
        effort: 'Endurance',
        laps: ordered.sublist(w, w + m),
      ),
      SwimIntervalSet(
        id: 'cool',
        label: 'Cool down',
        kind: SwimSetKind.cool,
        effort: 'Easy',
        laps: ordered.sublist(w + m, n),
      ),
    ];
  }
  final block = (n / 4).ceil();
  final out = <SwimIntervalSet>[];
  for (var b = 0, start = 0; start < n; b++, start += block) {
    final end = math.min(n, start + block);
    final kind = b == 0
        ? SwimSetKind.warmup
        : (end >= n ? SwimSetKind.cool : SwimSetKind.block);
    out.add(
      SwimIntervalSet(
        id: 'block${b + 1}',
        label: 'Block ${b + 1}',
        kind: kind,
        effort: b == 0
            ? 'Build'
            : (end >= n ? 'Fade watch' : 'Main effort'),
        laps: ordered.sublist(start, end),
      ),
    );
  }
  return out;
}

/// Collapsible sets with horizontal length bars (MySwimPro-inspired).
class SwimIntervalSetsView extends StatefulWidget {
  const SwimIntervalSetsView({
    super.key,
    required this.laps,
    this.poolLengthM,
    this.showDevIndex = false,
  });

  final List<SwimLapMetrics> laps;
  final int? poolLengthM;
  final bool showDevIndex;

  @override
  State<SwimIntervalSetsView> createState() => _SwimIntervalSetsViewState();
}

class _SwimIntervalSetsViewState extends State<SwimIntervalSetsView> {
  late Set<String> _open;

  @override
  void initState() {
    super.initState();
    _open = {_preferredSetId(buildSwimIntervalSets(widget.laps))}.difference({''});
  }

  @override
  void didUpdateWidget(covariant SwimIntervalSetsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.laps.length != widget.laps.length) {
      _open = {_preferredSetId(buildSwimIntervalSets(widget.laps))}
          .difference({''});
    }
  }

  String _preferredSetId(List<SwimIntervalSet> sets) {
    for (final s in sets) {
      if (s.id == 'main') return s.id;
    }
    return sets.isEmpty ? '' : sets.first.id;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.laps.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sets = buildSwimIntervalSets(widget.laps);
    final maxDur = widget.laps
        .map((l) => l.durationSec ?? 0)
        .fold<int>(1, (a, b) => math.max(a, b));
    final sessionAvgPace = _avgPace(widget.laps);
    final pool = widget.poolLengthM;

    return Card(
      key: const Key('swim-interval-sets'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Intervals',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${widget.laps.length} lengths · tap a set to expand',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final set in sets) ...[
              _SetCard(
                set: set,
                open: _open.contains(set.id),
                poolLengthM: pool,
                maxDur: maxDur,
                sessionAvgPace: sessionAvgPace,
                showDevIndex: widget.showDevIndex,
                onToggle: () {
                  setState(() {
                    if (_open.contains(set.id)) {
                      _open.remove(set.id);
                    } else {
                      _open.add(set.id);
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  int? _avgPace(List<SwimLapMetrics> laps) {
    final paced = laps
        .map((l) => l.paceSecPer100m)
        .whereType<int>()
        .where((p) => p > 0)
        .toList();
    if (paced.isEmpty) return null;
    return (paced.reduce((a, b) => a + b) / paced.length).round();
  }
}

class _SetCard extends StatelessWidget {
  const _SetCard({
    required this.set,
    required this.open,
    required this.poolLengthM,
    required this.maxDur,
    required this.sessionAvgPace,
    required this.showDevIndex,
    required this.onToggle,
  });

  final SwimIntervalSet set;
  final bool open;
  final int? poolLengthM;
  final int maxDur;
  final int? sessionAvgPace;
  final bool showDevIndex;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = SwimChartColors.accent(context);
    final n = set.laps.length;
    final unit = poolLengthM != null && poolLengthM! > 0
        ? '$n × ${poolLengthM}m'
        : '$n lengths';
    final avgPace = _avgPace(set.laps);
    final meta = avgPace != null
        ? '${avgPace}s/100'
        : _fmtDur(
            set.laps.fold<int>(0, (a, l) => a + (l.durationSec ?? 0)),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        children: [
          InkWell(
            key: Key('swim-set-${set.id}'),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _dotColor(set.kind, accent),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${set.label} · ${n}x',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          unit,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    meta,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.expand_more,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '${set.effort} effort'.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const Spacer(),
                      if (avgPace != null)
                        Text(
                          '$avgPace/100 AVG',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < set.laps.length; i++)
                    _LengthRow(
                      displayIndex: i + 1,
                      lap: set.laps[i],
                      maxDur: maxDur,
                      sessionAvgPace: sessionAvgPace,
                      showDevIndex: showDevIndex,
                      accent: accent,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _dotColor(SwimSetKind kind, Color accent) => switch (kind) {
        SwimSetKind.warmup => Color.lerp(accent, Colors.grey, 0.35)!,
        SwimSetKind.main => accent,
        SwimSetKind.cool => SwimChartColors.amber,
        SwimSetKind.block => SwimChartColors.mint,
      };

  int? _avgPace(List<SwimLapMetrics> laps) {
    final paced = laps
        .map((l) => l.paceSecPer100m)
        .whereType<int>()
        .where((p) => p > 0)
        .toList();
    if (paced.isEmpty) return null;
    return (paced.reduce((a, b) => a + b) / paced.length).round();
  }
}

class _LengthRow extends StatelessWidget {
  const _LengthRow({
    required this.displayIndex,
    required this.lap,
    required this.maxDur,
    required this.sessionAvgPace,
    required this.showDevIndex,
    required this.accent,
  });

  final int displayIndex;
  final SwimLapMetrics lap;
  final int maxDur;
  final int? sessionAvgPace;
  final bool showDevIndex;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dur = lap.durationSec ?? 0;
    final workPct = math.max(0.08, dur / math.max(1, maxDur));
    final pace = lap.paceSecPer100m;
    final slow = pace != null &&
        sessionAvgPace != null &&
        pace > sessionAvgPace! + 3;
    final barColor = slow ? SwimChartColors.amber : accent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              showDevIndex ? '${lap.index + 1}' : '#$displayIndex',
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          SwimStrokeIcon(style: lap.style),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 18,
                color: scheme.onSurface.withValues(alpha: 0.05),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: workPct.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(barColor, Colors.black, 0.15)!,
                          barColor,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmtDur(dur),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  pace != null
                      ? '${pace}s'
                      : (lap.swolf != null ? 'SW ${lap.swolf}' : '—'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDur(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
