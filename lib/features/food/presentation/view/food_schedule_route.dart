import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/food/presentation/view/food_schedule_screen.dart';

/// Route for food schedule config.
class FoodScheduleRoute {
  static const path = '/food/schedule';

  static void register() {
    AppRouter.register(
      path,
      (context) => const FoodScheduleScreen(),
    );
  }

  static Route<void> route(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const FoodScheduleScreen(),
    );
  }
}
