import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_detail_screen.dart';

class SleepDetailRoute {
  static const String path = '/sleep_detail';

  static void register() {
    AppRouter.register(
      path,
      (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is! SleepSessionSummary) {
          return const Scaffold(
            body: Center(child: Text('Sleep session not found')),
          );
        }
        return SleepDetailScreen(session: args);
      },
    );
  }

  static void go(BuildContext context, SleepSessionSummary session) {
    Navigator.pushNamed(context, path, arguments: session);
  }
}
