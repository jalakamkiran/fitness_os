import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

enum WorkoutSportTab { swim, run, strength }

/// Top sport switcher for the Workouts tab.
class SportTabs extends StatelessWidget {
  const SportTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final WorkoutSportTab selected;
  final ValueChanged<WorkoutSportTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);

    return Semantics(
      container: true,
      label: 'Sport',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.bgElev,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: _Tab(
                label: 'Swim',
                selected: selected == WorkoutSportTab.swim,
                onTap: () => onSelected(WorkoutSportTab.swim),
              ),
            ),
            Expanded(
              child: _Tab(
                label: 'Run',
                selected: selected == WorkoutSportTab.run,
                onTap: () => onSelected(WorkoutSportTab.run),
              ),
            ),
            Expanded(
              child: _Tab(
                label: 'Strength',
                selected: selected == WorkoutSportTab.strength,
                onTap: () => onSelected(WorkoutSportTab.strength),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? Color.lerp(colors.accent, colors.bgElev, 0.82) ?? colors.bgElev
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? colors.ink : colors.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}
