import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_stage_mapping.dart';

/// Horizontal hypnogram of sleep stage blocks (message-path or SEQUENCE).
class SleepHypnogram extends StatelessWidget {
  const SleepHypnogram({super.key, required this.stages});

  final List<SleepStageSummary> stages;

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) return const SizedBox.shrink();
    final colors = FathomColors.of(context);
    final segments = <(int flex, Color color)>[
      for (final s in stages)
        (
          s.durationMin.clamp(1, 24 * 60),
          sleepStageColorForWireType(context, s.wireType),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              painter: _HypnogramPainter(
                segments: segments,
                trackColor: colors.line,
              ),
              child: const SizedBox.expand(),
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

class _HypnogramPainter extends CustomPainter {
  _HypnogramPainter({
    required this.segments,
    required this.trackColor,
  });

  final List<(int flex, Color color)> segments;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);
    final total = segments.fold<int>(0, (sum, s) => sum + s.$1);
    if (total <= 0 || size.width <= 0) return;
    var x = 0.0;
    for (final (flex, color) in segments) {
      final w = size.width * (flex / total);
      canvas.drawRect(
        Rect.fromLTWH(x, 0, w.clamp(0.0, size.width - x), size.height),
        Paint()..color = color,
      );
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant _HypnogramPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.trackColor != trackColor;
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
