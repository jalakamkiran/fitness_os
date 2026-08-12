import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_stage_mapping.dart';

/// Horizontal hypnogram of message-path stage blocks.
class SleepHypnogram extends StatelessWidget {
  const SleepHypnogram({super.key, required this.stages});

  final List<SleepStageSummary> stages;

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) return const SizedBox.shrink();
    final colors = FathomColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                for (final s in stages)
                  Expanded(
                    flex: s.durationMin.clamp(1, 24 * 60),
                    child: ColoredBox(
                      color: sleepStageColorForWireType(context, s.wireType),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _Legend(color: colors.inkDim, label: 'Light'),
            _Legend(color: colors.accent, label: 'Deep'),
            _Legend(color: colors.amber, label: 'REM'),
            _Legend(color: colors.hot, label: 'Awake'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

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
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: FathomTextStyles.mono(
            fontSize: 11,
            color: FathomColors.of(context).inkFaint,
          ),
        ),
      ],
    );
  }
}
