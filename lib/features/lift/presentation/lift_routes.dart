import 'package:flutter/material.dart';
import 'package:fitness_os/core/feature_flags.dart';
import 'package:fitness_os/features/lift/presentation/view/lift_debug_screen.dart';
import 'package:fitness_os/features/lift/presentation/view/lift_home_screen.dart';

class LiftRoutes {
  static const home = '/lift/home';
  static const debug = '/lift/debug';

  static void register() {}

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (!FeatureFlags.liftWatch) return null;
    switch (settings.name) {
      case home:
        return MaterialPageRoute<void>(builder: (_) => const LiftHomeScreen());
      case debug:
        return MaterialPageRoute<void>(builder: (_) => const LiftDebugScreen());
    }
    return null;
  }
}