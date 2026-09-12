import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';

/// Pace-block splits — shown only when blocks have distance and/or pace.
///
/// [narrative] matches `run-analytics.html`: Fastest / Walk tags + elapsed.
class RunPaceSplitsTable extends StatelessWidget {
  const RunPaceSplitsTable({
    super.key,
    required this.splits,
    this.narrative = false,
  });

  final List<RunPaceSplit> splits;

  /// Product narrative layout (km · pace · time · tag).
  final bool narrative;

  @override
  Widget build(BuildContext context) {
    if (narrative) {
      return _NarrativeSplits(splits: splits);
    }
    return _LegacySplitsTable(splits: splits);
  }
}

class _NarrativeSplits extends StatelessWidget {
  const _NarrativeSplits({required this.splits});

  final List<RunPaceSplit> splits;

  @override
  Widget build(BuildContext context) {
    final rows = annotateRunSplits(splits);
    if (rows.isEmpty) return const SizedBox.shrink();

    final colors = FathomColors.of(context);
    final theme = Theme.of(context);
    final hasWalk = rows.any((r) => r.isWalk);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.bgElev,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    _Head(colors, 'Km', flex: 2),
                    _Head(colors, 'Pace', flex: 3),
                    _Head(colors, 'Time', flex: 3),
                    const Expanded(flex: 4, child: SizedBox.shrink()),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.line),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.line.withValues(alpha: 0.8)),
                _SplitRow(row: rows[i], colors: colors, theme: theme),
              ],
            ],
          ),
        ),
        if (hasWalk) ...[
          const SizedBox(height: 8),
          Text(
            'Mode change tagged — walk km not scored as fade',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.inkFaint,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.colors, this.label, {required this.flex});

  final FathomColors colors;
  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.inkFaint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.row,
    required this.colors,
    required this.theme,
  });

  final AnnotatedRunSplit row;
  final FathomColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final pace = formatPaceSecPerKm(row.split.paceSec) ?? '—';
    final time = formatDurationClock(row.elapsedSec);
    final dist = row.split.distanceM;
    final partial = dist != null && dist > 0 && dist < 950;
    String? tag;
    Color? tagColor;
    Color? bg;
    if (row.isFastest) {
      tag = 'Fastest';
      tagColor = colors.up;
      bg = Color.lerp(colors.bgElev, colors.up, 0.08);
    } else if (row.isWalk) {
      tag = partial ? '${(dist / 1000).toStringAsFixed(2)} · Walk' : 'Walk';
      tagColor = colors.amber;
      bg = Color.lerp(colors.bgElev, colors.amber, 0.07);
    } else {
      tag = 'Run';
      tagColor = colors.inkFaint;
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '${row.index + 1}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'IBM Plex Mono',
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              pace,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'IBM Plex Mono',
                fontWeight: FontWeight.w600,
                color: row.isWalk ? colors.amber : colors.accent,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              time,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'IBM Plex Mono',
                color: colors.inkDim,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                tag.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  fontSize: 10,
                  color: tagColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegacySplitsTable extends StatelessWidget {
  const _LegacySplitsTable({required this.splits});

  final List<RunPaceSplit> splits;

  @override
  Widget build(BuildContext context) {
    final chartable =
        splits.where((s) => s.hasDistanceOrPace).toList(growable: false);
    if (chartable.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Splits',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Watch pace blocks · this run',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 44,
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Distance')),
                  DataColumn(label: Text('Pace')),
                ],
                rows: [
                  for (var i = 0; i < chartable.length; i++)
                    DataRow(
                      cells: [
                        DataCell(Text('${i + 1}')),
                        DataCell(
                          Text(formatDistanceM(chartable[i].distanceM)),
                        ),
                        DataCell(
                          Text(
                            formatPaceSecPerKm(chartable[i].paceSec) ?? '—',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
