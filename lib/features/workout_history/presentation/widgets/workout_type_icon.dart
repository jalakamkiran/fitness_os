import 'package:flutter/material.dart';
import 'package:fitness_os/features/workout_history/domain/huawei_workout_types.dart';

/// Icon for workout type based on category.
///
/// Uses Material Icons to represent different workout categories.
/// Falls back to a generic sports icon for unknown types.
class WorkoutTypeIcon extends StatelessWidget {
  const WorkoutTypeIcon({
    super.key,
    required this.type,
    this.size = 24,
    this.color,
  });

  final int type;
  final double size;
  final Color? color;

  IconData _iconForType(int type) {
    final category = workoutTypeCategory(type);
    
    // Special cases for specific types
    if (type == 140) return Icons.fitness_center; // Strength
    if (type == 6 || type == 8) return Icons.pool; // Swimming
    if (type == 1) return Icons.directions_walk; // Walk
    if (type == 2 || type == 5) return Icons.directions_run; // Run
    if (type == 3 || type == 7) return Icons.directions_bike; // Cycling
    if (type == 10) return Icons.rowing; // Rowing
    if (type == 4 || type == 11) return Icons.terrain; // Climbing/Hiking
    if (type == 141) return Icons.self_improvement; // Yoga
    if (type == 146) return Icons.rotate_90_degrees_ccw; // Jump rope
    
    // Category-based icons
    return switch (category) {
      WorkoutCategory.cardio => Icons.favorite,
      WorkoutCategory.cycling => Icons.pedal_bike,
      WorkoutCategory.swimming => Icons.pool,
      WorkoutCategory.outdoor => Icons.landscape,
      WorkoutCategory.racket => Icons.sports_tennis,
      WorkoutCategory.ballSports => Icons.sports_basketball,
      WorkoutCategory.winter => Icons.downhill_skiing,
      WorkoutCategory.strength => Icons.fitness_center,
      WorkoutCategory.flexibility => Icons.self_improvement,
      WorkoutCategory.combat => Icons.sports_martial_arts,
      WorkoutCategory.other => Icons.sports,
      null => Icons.sports,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Icon(
      _iconForType(type),
      size: size,
      color: color,
    );
  }
}
