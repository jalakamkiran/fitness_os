import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/domain/strength_session_metrics.dart';

/// Product strength session body — mirrors `docs/design/strength-analytics.html`.
class StrengthSessionAnalytics extends StatelessWidget {
  const StrengthSessionAnalytics({
    super.key,
    required this.workout,
    this.historyOverride,
    this.onExport,
    this.exportBusy = false,
    this.onAllSessions,
  });

  final WorkoutSummary workout;

  /// Test seam — when set, skips repository load for recent-load bars.
  final List<WorkoutSummary>? historyOverride;

  final VoidCallback? onExport;
  final bool exportBusy;
  final VoidCallback? onAllSessions;

  @override
  Widget build(BuildContext context) {
    final metrics = StrengthSessionMetrics(workout);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metrics.hasBasics) ...[
          _BasicsRow(metrics: metrics),
          const SizedBox(height: 14),
        ],
        if (metrics.hasImpact) ...[
          _SectionKicker('This session'),
          const SizedBox(height: 10),
          _ImpactRow(metrics: metrics),
          const SizedBox(height: 14),
        ],
        if (metrics.hasIntensity) ...[
          _SectionKicker('Intensity'),
          const SizedBox(height: 10),
          _IntensityGrid(metrics: metrics),
          const SizedBox(height: 14),
        ],
        _RecentLoadCard(
          current: workout,
          historyOverride: historyOverride,
        ),
        const SizedBox(height: 14),
        _SectionKicker('After this session'),
        const SizedBox(height: 10),
        const _AfterSessionCard(),
        if (onExport != null || onAllSessions != null) ...[
          const SizedBox(height: 16),
          if (onExport != null) ...[
            FilledButton(
              onPressed: exportBusy ? null : onExport,
              child: exportBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Export session'),
            ),
            const SizedBox(height: 8),
          ],
          if (onAllSessions != null)
            OutlinedButton(
              onPressed: onAllSessions,
              child: const Text('All strength sessions'),
            ),
        ],
      ],
    );
  }
}

class _SectionKicker extends StatelessWidget {
  const _SectionKicker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: colors.inkDim,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _BasicsRow extends StatelessWidget {
  const _BasicsRow({required this.metrics});

  final StrengthSessionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final cells = <({String label, String value})>[
      if (metrics.durationLabel != null)
        (label: 'Duration', value: metrics.durationLabel!),
      if (metrics.caloriesLabel != null)
        (label: 'Calories', value: metrics.caloriesLabel!),
      if (metrics.hrRangeLabel != null)
        (label: 'Heart rate', value: metrics.hrRangeLabel!),
    ];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              decoration: BoxDecoration(
                color: Color.lerp(colors.bgElev, colors.accent, 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.line.withValues(alpha: 0.7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cells[i].label.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.inkDim,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          fontSize: 10,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cells[i].value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontFamily: 'IBM Plex Mono',
                          fontWeight: FontWeight.w500,
                          color: colors.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({required this.metrics});

  final StrengthSessionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final cards = <({String label, String value, String hint})>[
      if (metrics.loadLabel != null)
        (
          label: 'Training load',
          value: metrics.loadLabel!,
          hint: 'How hard this session was',
        ),
      if (metrics.recoveryTimeLabel != null)
        (
          label: 'Recovery time',
          value: metrics.recoveryTimeLabel!,
          hint: 'Suggested before the next hard effort',
        ),
    ];
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              decoration: BoxDecoration(
                color: colors.bgElev,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cards[i].label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.inkDim,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cards[i].value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontFamily: 'IBM Plex Mono',
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                      letterSpacing: -0.5,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cards[i].hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.inkFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _IntensityGrid extends StatelessWidget {
  const _IntensityGrid({required this.metrics});

  final StrengthSessionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final cells = <({String label, String value})>[
      if (metrics.caloriesPerMinLabel != null)
        (label: 'Calories / min', value: metrics.caloriesPerMinLabel!),
      if (metrics.loadPerHourLabel != null)
        (label: 'Load / hour', value: metrics.loadPerHourLabel!),
      if (metrics.aerobicLabel != null)
        (label: 'Aerobic', value: metrics.aerobicLabel!),
      if (metrics.anaerobicLabel != null)
        (label: 'Anaerobic', value: metrics.anaerobicLabel!),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cell in cells)
              SizedBox(
                width: cellW,
                child: _IntensityCell(label: cell.label, value: cell.value),
              ),
          ],
        );
      },
    );
  }
}

class _IntensityCell extends StatelessWidget {
  const _IntensityCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.inkFaint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'IBM Plex Mono',
              fontWeight: FontWeight.w500,
              color: colors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentLoadCard extends StatefulWidget {
  const _RecentLoadCard({
    required this.current,
    this.historyOverride,
  });

  final WorkoutSummary current;
  final List<WorkoutSummary>? historyOverride;

  @override
  State<_RecentLoadCard> createState() => _RecentLoadCardState();
}

class _RecentLoadCardState extends State<_RecentLoadCard> {
  Future<List<WorkoutSummary>>? _historyFuture;

  @override
  void initState() {
    super.initState();
    if (widget.historyOverride == null) {
      _historyFuture = _loadLocalHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.historyOverride != null) {
      return _RecentLoadBody(
        current: widget.current,
        history: widget.historyOverride!,
        loading: false,
      );
    }
    return FutureBuilder<List<WorkoutSummary>>(
      future: _historyFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _RecentLoadBody(
            current: widget.current,
            history: const [],
            loading: true,
          );
        }
        return _RecentLoadBody(
          current: widget.current,
          history: snap.data ?? const [],
          loading: false,
        );
      },
    );
  }
}

Future<List<WorkoutSummary>> _loadLocalHistory() async {
  try {
    return await sl<WorkoutHistoryRepository>().loadLocal();
  } catch (_) {
    return const [];
  }
}

class _RecentLoadBody extends StatelessWidget {
  const _RecentLoadBody({
    required this.current,
    required this.history,
    this.loading = false,
  });

  final WorkoutSummary current;
  final List<WorkoutSummary> history;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();

    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final recent = recentStrengthLoads(current: current, all: history);
    final loads = recent.map((w) => w.load).toList();
    // Require at least one known load (including 0). All-null → hide.
    final hasAnyKnown = loads.any((l) => l != null);
    if (!hasAnyKnown) return const SizedBox.shrink();

    final maxLoad = loads
        .whereType<int>()
        .fold<int>(0, (a, b) => a > b ? a : b)
        .clamp(1, 1 << 30);

    return Container(
      padding: const EdgeInsets.all(14),
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
                  'Recent training load',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ),
              Text(
                'Last ${recent.length} sessions',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'IBM Plex Mono',
                  color: colors.inkFaint,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: _LoadBar(
                      load: recent[i].load,
                      maxLoad: maxLoad,
                      isCurrent: recent[i].number == current.number &&
                          recent[i].startTime == current.startTime,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Earlier',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'IBM Plex Mono',
                  color: colors.inkFaint,
                  fontSize: 10,
                ),
              ),
              Text(
                'This session',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'IBM Plex Mono',
                  color: colors.inkFaint,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadBar extends StatelessWidget {
  const _LoadBar({
    required this.load,
    required this.maxLoad,
    required this.isCurrent,
  });

  final int? load;
  final int maxLoad;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final value = load;
    final heightFrac = value == null
        ? 0.0
        : value <= 0
            ? 0.06
            : (value / maxLoad).clamp(0.08, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight * heightFrac;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              if (value != null)
                Container(
                  height: h,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? colors.accent
                        : Color.lerp(colors.line, colors.accent, 0.55),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                      bottom: Radius.circular(2),
                    ),
                  ),
                )
              else
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.line.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              if (value != null)
                Positioned(
                  bottom: -16,
                  child: Text(
                    '$value',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFamily: 'IBM Plex Mono',
                          color: colors.inkFaint,
                          fontSize: 8,
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

class _AfterSessionCard extends StatelessWidget {
  const _AfterSessionCard();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ContextRow(
          title: 'Sleep',
          tag: 'Night after',
          value: 'Waiting for data',
        ),
        SizedBox(height: 8),
        _ContextRow(
          title: 'How you felt',
          tag: 'Morning check-in',
          value: 'Not logged',
        ),
      ],
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({
    required this.title,
    required this.tag,
    required this.value,
  });

  final String title;
  final String tag;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tag.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.inkFaint,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'IBM Plex Mono',
              color: colors.inkDim,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
