import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/domain/daily_food_totals.dart';
import 'package:fitness_os/features/food/domain/food_meal.dart';
import 'package:fitness_os/features/food/presentation/view/food_capture_route.dart';
import 'package:fitness_os/features/food/presentation/view/food_meal_edit_route.dart';
import 'package:fitness_os/features/food/presentation/widgets/food_meal_row.dart';

/// Food subtab screen: day history with meals or empty state.
class FoodTabScreen extends StatefulWidget {
  const FoodTabScreen({
    this.store,
    this.imageBuilder,
    super.key,
  });

  /// Optional store for tests; defaults to GetIt.
  final FoodMealStore? store;
  
  /// Test seam: bypass async Image.file in tests.
  final Widget Function(File)? imageBuilder;

  @override
  State<FoodTabScreen> createState() => _FoodTabScreenState();
}

class _FoodTabScreenState extends State<FoodTabScreen> {
  late FoodMealStore _store;
  String _selectedDayKey = '';
  DailyFoodTotals? _dayTotals;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? GetIt.I<FoodMealStore>();
    _selectedDayKey = _formatDayKey(DateTime.now());
    _loadDay();
  }

  Future<void> _loadDay() async {
    setState(() => _isLoading = true);
    try {
      final totals = await _store.loadDayTotals(_selectedDayKey);
      if (mounted) {
        setState(() {
          _dayTotals = totals;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _switchDay(int dayOffset) {
    final currentDate = DateTime.parse(_selectedDayKey);
    final newDate = currentDate.add(Duration(days: dayOffset));
    setState(() {
      _selectedDayKey = _formatDayKey(newDate);
    });
    _loadDay();
  }

  Future<void> _onLogMeal() async {
    await Navigator.pushNamed(context, FoodCaptureRoute.path);
    _loadDay();
  }

  Future<void> _onMealTap(FoodMeal meal) async {
    final result = await Navigator.pushNamed(
      context,
      FoodMealEditRoute.path,
      arguments: {
        'meal': meal,
        'processImage': null,
      },
    );
    
    if (result == true) {
      // Meal was edited or deleted, reload
      _loadDay();
    }
  }

  String _formatDayKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  bool _isToday() {
    return _selectedDayKey == _formatDayKey(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(colors.accent),
        ),
      );
    }

    final meals = _dayTotals?.meals ?? [];
    final isEmpty = meals.isEmpty;

    return Column(
      children: [
        // Day navigation
        _buildDayNavigation(colors, theme),
        
        // Content
        Expanded(
          child: isEmpty
              ? _buildEmptyState(colors, theme)
              : _buildMealsList(colors, theme, meals),
        ),
      ],
    );
  }

  Widget _buildDayNavigation(FathomColors colors, ThemeData theme) {
    final isToday = _isToday();
    final date = DateTime.parse(_selectedDayKey);
    final dateText = isToday
        ? 'Today'
        : '${_monthName(date.month)} ${date.day}, ${date.year}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: colors.ink),
            onPressed: () => _switchDay(-1),
          ),
          Expanded(
            child: Text(
              dateText,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: isToday ? colors.inkFaint : colors.ink,
            ),
            onPressed: isToday ? null : () => _switchDay(1),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(FathomColors colors, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Icon(
            Icons.restaurant_outlined,
            size: 64,
            color: colors.inkFaint,
          ),
          const SizedBox(height: 16),
          Text(
            'No meals logged',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start tracking your meals with photos',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.inkFaint,
            ),
          ),
          const SizedBox(height: 48),
          _ActionButton(
            label: 'Log meal',
            icon: Icons.add_a_photo_outlined,
            onTap: _onLogMeal,
          ),
          const SizedBox(height: 16),
          _ActionButton(
            label: 'Set meal times',
            icon: Icons.schedule_outlined,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Meal schedule coming soon'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMealsList(
    FathomColors colors,
    ThemeData theme,
    List<FoodMeal> meals,
  ) {
    return Column(
      children: [
        // Daily total header
        _buildDailyTotalHeader(colors, theme),
        
        // Meals list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: meals.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final meal = meals[index];
              return FoodMealRow(
                meal: meal,
                onTap: () => _onMealTap(meal),
                imageBuilder: widget.imageBuilder,
              );
            },
          ),
        ),
        
        // FAB for adding meals
        Padding(
          padding: const EdgeInsets.all(16),
          child: FloatingActionButton.extended(
            onPressed: _onLogMeal,
            backgroundColor: colors.accent,
            icon: Icon(Icons.add, color: colors.bg),
            label: Text(
              'Log meal',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.bg,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyTotalHeader(FathomColors colors, ThemeData theme) {
    final totals = _dayTotals;
    if (totals == null) return const SizedBox.shrink();

    final totalKcal = totals.totalKcal;
    final isIncomplete = totals.isIncomplete;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.bgElev,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.inkFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (totalKcal != null)
                  Row(
                    children: [
                      Text(
                        '${totalKcal.round()} kcal',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.ink,
                        ),
                      ),
                      if (isIncomplete) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.line),
                          ),
                          child: Text(
                            'incomplete',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.inkFaint,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  Text(
                    'No calorie data',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${totals.mealCount} meal${totals.mealCount == 1 ? '' : 's'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Material(
      color: Color.lerp(colors.accent, colors.bgElev, 0.82) ?? colors.bgElev,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                color: colors.accent,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios,
                color: colors.inkFaint,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
