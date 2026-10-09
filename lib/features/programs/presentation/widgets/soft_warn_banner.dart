import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/domain/soft_load_warn.dart';

/// Calm factual banner for heavy other-sport load. Amber, never red shame.
class SoftWarnBanner extends StatelessWidget {
  const SoftWarnBanner({super.key, required this.result});

  final SoftLoadWarnResult result;

  @override
  Widget build(BuildContext context) {
    if (!result.warn) return const SizedBox.shrink();
    final colors = FathomColors.of(context);
    final amberLine = Color.lerp(colors.amber, colors.line, 0.68)!;
    final amberWash = Color.lerp(colors.amber, colors.bgElev, 0.9)!;

    return Container(
      key: const Key('programs-soft-warn'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: amberWash,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amberLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.amber.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Text(
              '!',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.ink,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Other load today',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  result.copy.isEmpty
                      ? 'Recent non-swim activity looks heavy for you. Today’s swim stays on the course.'
                      : '${result.copy}. Today’s swim stays on the course.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.inkDim,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Soft warning · you decide.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.inkFaint,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
