import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/domain/soft_load_warn.dart';

/// Calm factual banner for heavy other-sport load. Never a readiness score.
class SoftWarnBanner extends StatelessWidget {
  const SoftWarnBanner({super.key, required this.result});

  final SoftLoadWarnResult result;

  @override
  Widget build(BuildContext context) {
    if (!result.warn) return const SizedBox.shrink();
    final colors = FathomColors.of(context);
    return Container(
      key: const Key('programs-soft-warn'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.pool,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.poolLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Other load today',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            result.copy.isEmpty
                ? 'Recent non-swim activity looks heavy for you. Today’s swim stays on the plan.'
                : '${result.copy}. Today’s swim stays on the plan.',
            style: TextStyle(fontSize: 13, color: colors.inkDim, height: 1.35),
          ),
        ],
      ),
    );
  }
}
