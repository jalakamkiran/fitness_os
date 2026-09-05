import 'package:fitness_os/features/food/domain/food_meal.dart';

/// Daily aggregate of meals with incomplete flag when any meal lacks kcal.
class DailyFoodTotals {
  const DailyFoodTotals({
    required this.dayKey,
    required this.meals,
  });

  final String dayKey;
  final List<FoodMeal> meals;

  /// Total kcal from meals that have kcal provided; null if no meals have kcal.
  double? get totalKcal {
    final withKcal = meals.where((m) => m.kcal != null).toList();
    if (withKcal.isEmpty) return null;
    return withKcal.fold<double>(0.0, (sum, m) => sum + (m.kcal ?? 0.0));
  }

  /// True if any meal lacks kcal (incomplete logging).
  bool get isIncomplete => meals.any((m) => m.kcal == null);

  /// Number of meals logged for the day.
  int get mealCount => meals.length;
}
