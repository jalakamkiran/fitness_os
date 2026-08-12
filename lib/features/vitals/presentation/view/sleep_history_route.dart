import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_history_screen.dart';

class SleepHistoryRoute {
  static const String path = '/sleep_history';

  static void register() {
    AppRouter.register(
      path,
      (context) => const SleepHistoryScreen(),
    );
  }

  static void go(BuildContext context) {
    Navigator.pushNamed(context, path);
  }
}
