import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/app/shell/app_shell.dart';

class AppShellRoute {
  static const String path = '/';

  static void register({
    Widget? homeBody,
    Widget? vitalsBody,
    Widget? workoutsBody,
  }) {
    AppRouter.register(
      path,
      (context) => AppShell(
        homeBody: homeBody,
        vitalsBody: vitalsBody,
        workoutsBody: workoutsBody,
      ),
    );
  }
}
