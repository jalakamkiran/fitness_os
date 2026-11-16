import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/huawei_workout_types.dart';

/// Multi-select sport filter chips for the Sports tab.
///
/// Shows chips for workout types present in the user's history plus
/// known Huawei sport types. Designed for future per-sport analytics.
class SportsFilterChips extends StatelessWidget {
  const SportsFilterChips({
    super.key,
    required this.availableTypes,
    required this.selectedTypes,
    required this.onSelectionChanged,
  });

  /// Sport type codes present in user's workout history.
  final Set<int> availableTypes;

  /// Currently selected sport types (empty = all).
  final Set<int> selectedTypes;

  /// Callback when selection changes.
  final ValueChanged<Set<int>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FathomColors.of(context);

    // Build list of sport types to show: user's types + known sports
    final typesToShow = <int>{...availableTypes, ..._knownSportTypes()};
    final sortedTypes = typesToShow.toList()..sort();

    if (sortedTypes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter by sport',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.inkDim,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // "All" chip
              _FilterChip(
                label: 'All',
                selected: selectedTypes.isEmpty,
                onTap: () => onSelectionChanged({}),
                colors: colors,
              ),
              // Individual sport chips
              for (final type in sortedTypes)
                _FilterChip(
                  label: workoutTypeLabel(type),
                  selected: selectedTypes.contains(type),
                  onTap: () {
                    final newSelection = Set<int>.from(selectedTypes);
                    if (newSelection.contains(type)) {
                      newSelection.remove(type);
                    } else {
                      newSelection.add(type);
                    }
                    onSelectionChanged(newSelection);
                  },
                  colors: colors,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Known Huawei sport types that should always appear in the filter.
  ///
  /// Covers the major sport categories users might record:
  /// - Racket: Badminton, Tennis, Table tennis, Squash
  /// - Ball: Football, Basketball, Volleyball
  /// - Other popular: Cycling, Yoga, Boxing
  Set<int> _knownSportTypes() {
    return {
      129, // Badminton
      130, // Table tennis
      131, // Tennis
      133, // Squash
      134, // Basketball
      135, // Football
      137, // Volleyball
      3, // Cycle
      7, // Indoor cycle
      141, // Yoga
      143, // Boxing
    };
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FathomColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? Color.lerp(colors.accent, colors.bgElev, 0.75)
          : colors.bgElev,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.accent : colors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.ink : colors.inkDim,
            ),
          ),
        ),
      ),
    );
  }
}
