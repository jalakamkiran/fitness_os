import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/diagnostics/presentation/view/advanced_tools_screen.dart';

class AdvancedToolsRoute {
  static const String path = '/advanced_tools';

  static void register() {
    AppRouter.register(
      path,
      (context) => const AdvancedToolsScreen(),
    );
  }

  static void go(BuildContext context) {
    Navigator.pushNamed(context, path);
  }
}
