import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/workout_history/presentation/view/coach_settings_screen.dart';

class CoachSettingsRoute {
  static const String path = '/coach_settings';

  static void register() {
    AppRouter.register(
      path,
      (context) => const CoachSettingsScreen(),
    );
  }

  static void go(BuildContext context) {
    Navigator.pushNamed(context, path);
  }
}
