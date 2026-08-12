import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

enum RecoverySubtab { vitals, sleep }

/// SportTabs-style segmented switcher for Recovery: Vitals | Sleep.
class RecoverySubtabs extends StatelessWidget {
  const RecoverySubtabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final RecoverySubtab selected;
  final ValueChanged<RecoverySubtab> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);

    return Semantics(
      container: true,
      label: 'Recovery section',
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
                label: 'Vitals',
                selected: selected == RecoverySubtab.vitals,
                onTap: () => onSelected(RecoverySubtab.vitals),
              ),
            ),
            Expanded(
              child: _Tab(
                label: 'Sleep',
                selected: selected == RecoverySubtab.sleep,
                onTap: () => onSelected(RecoverySubtab.sleep),
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
