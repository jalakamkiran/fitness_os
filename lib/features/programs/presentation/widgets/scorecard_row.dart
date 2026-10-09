import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/domain/scorecards.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_format.dart';
import 'package:fitness_os/features/programs/presentation/widgets/agon_chrome.dart';

/// Habit / Volume / Efficiency scorecards (capability layer).
class ScorecardRow extends StatelessWidget {
  const ScorecardRow({super.key, required this.bundle});

  final ScorecardBundle bundle;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Column(
      key: const Key('programs-scorecards'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: 'Habit',
          body: bundle.habit.displayFraction,
          focus: bundle.habit.focusLine,
          colors: colors,
        ),
        const SizedBox(height: 10),
        _Card(
          title: 'Volume',
          body: bundle.volume.capacityGapM <= 0
              ? '${formatMeters(bundle.volume.longestContinuousM)} m continuous'
              : '${formatMeters(bundle.volume.longestContinuousM)} m · '
                  '${formatMeters(bundle.volume.capacityGapM)} m to next trial',
          focus: bundle.volume.focusLine,
          colors: colors,
        ),
        const SizedBox(height: 10),
        _Card(
          title: 'Efficiency',
          body: bundle.efficiency.status == EfficiencyStatus.collecting
              ? 'Collecting'
              : bundle.efficiency.focusLine,
          focus: bundle.efficiency.focusLine,
          colors: colors,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.body,
    required this.focus,
    required this.colors,
  });

  final String title;
  final String body;
  final String focus;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    return AgonCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayerTag(title),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            focus,
            style: TextStyle(fontSize: 13, color: colors.inkDim, height: 1.3),
          ),
        ],
      ),
    );
  }
}
