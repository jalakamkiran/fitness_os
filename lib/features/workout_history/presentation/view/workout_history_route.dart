import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_screen.dart';

class WorkoutHistoryRoute {
  static const String path = '/workout_history';

  static void register() {
    AppRouter.register(
      path,
      (context) => const WorkoutHistoryScreen(),
    );
  }

  static void go(BuildContext context) {
    Navigator.pushNamed(context, path);
  }
}
