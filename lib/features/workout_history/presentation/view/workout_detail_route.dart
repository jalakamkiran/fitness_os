import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_screen.dart';

class WorkoutDetailRoute {
  static const String path = '/workout_detail';

  static void register() {
    AppRouter.register(
      path,
      (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is! WorkoutSummary) {
          return const Scaffold(
            body: Center(child: Text('Workout not found')),
          );
        }
        return WorkoutDetailScreen(workout: args);
      },
    );
  }

  static void go(BuildContext context, WorkoutSummary workout) {
    Navigator.pushNamed(context, path, arguments: workout);
  }
}
