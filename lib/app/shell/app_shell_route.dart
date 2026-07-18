import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/app/shell/app_shell.dart';

class AppShellRoute {
  static const String path = '/';

  static void register({Widget? vitalsBody}) {
    AppRouter.register(
      path,
      (context) => AppShell(vitalsBody: vitalsBody),
    );
  }
}
