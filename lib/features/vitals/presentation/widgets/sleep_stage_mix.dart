import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_stage_mapping.dart';

class SleepStageMixRow {
  const SleepStageMixRow({
    required this.kind,
    required this.label,
    required this.mins,
    required this.pct,
  });

  final SleepStageKind kind;
  final String label;
  final int mins;
  final int pct;
}

/// Aggregate stage minutes by provisional kind for mix bars / chips.
List<SleepStageMixRow> sleepStageMix(List<SleepStageSummary> stages) {
  if (stages.isEmpty) return const [];
  final minsBy = <SleepStageKind, int>{};
  final labelBy = <SleepStageKind, String>{};
  var total = 0;
  for (final s in stages) {
    final kind = sleepStageKindFromWireType(s.wireType);
    minsBy[kind] = (minsBy[kind] ?? 0) + s.durationMin;
    labelBy.putIfAbsent(kind, () => sleepStageLabel(s.wireType));
    total += s.durationMin;
  }
  if (total <= 0) return const [];

  // Stable display order for known kinds; unknowns after.
  const order = [
    SleepStageKind.light,
    SleepStageKind.deep,
    SleepStageKind.rem,
    SleepStageKind.awake,
    SleepStageKind.unknown,
  ];
  final rows = <SleepStageMixRow>[];
  for (final kind in order) {
    final mins = minsBy[kind];
    if (mins == null || mins <= 0) continue;
    rows.add(
      SleepStageMixRow(
        kind: kind,
        label: labelBy[kind] ?? kind.name,
        mins: mins,
        pct: ((mins / total) * 100).round(),
      ),
    );
  }
  return rows;
}

/// Horizontal stage mix bars + duration/% (not a rainbow dashboard).
class SleepStageMixBars extends StatelessWidget {
  const SleepStageMixBars({super.key, required this.stages});

  final List<SleepStageSummary> stages;

  @override
  Widget build(BuildContext context) {
    final rows = sleepStageMix(stages);
    if (rows.isEmpty) return const SizedBox.shrink();
    final colors = FathomColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    row.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colors.inkDim,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (row.pct / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: colors.line,
                      color: sleepStageColor(context, row.kind),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 88,
                  child: Text(
                    '${sleepFormatDuration(row.mins * 60)} · ${row.pct}%',
                    textAlign: TextAlign.right,
                    style: FathomTextStyles.mono(
                      fontSize: 11,
                      color: colors.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Text(
          'provisional stage mapping · message path SoT',
          style: FathomTextStyles.mono(
            fontSize: 11,
            color: colors.inkFaint,
          ),
        ),
      ],
    );
  }
}

/// Compact provisional stage chips for Sleep list card.
class SleepStageChips extends StatelessWidget {
  const SleepStageChips({super.key, required this.stages});

  final List<SleepStageSummary> stages;

  @override
  Widget build(BuildContext context) {
    final rows = sleepStageMix(stages);
    if (rows.isEmpty) return const SizedBox.shrink();
    final colors = FathomColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final row in rows)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: sleepStageColor(context, row.kind),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${row.label} ${sleepFormatDuration(row.mins * 60)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.inkDim,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'stage labels provisional · message path',
          style: FathomTextStyles.mono(
            fontSize: 11,
            color: colors.inkFaint,
          ),
        ),
      ],
    );
  }
}
