import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';

/// Pace-block splits table — shown only when blocks have distance and/or pace.
///
/// No sample-derived splits this cut. Missing meta → [SizedBox.shrink].
class RunPaceSplitsTable extends StatelessWidget {
  const RunPaceSplitsTable({super.key, required this.splits});

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
              'Pace blocks · this run',
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
                        DataCell(Text(_paceCell(chartable[i].paceSec))),
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

  String _paceCell(int? paceSec) {
    if (paceSec == null || paceSec <= 0) return '—';
    final m = paceSec ~/ 60;
    final s = paceSec % 60;
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }
}
