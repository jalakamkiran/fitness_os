import 'package:flutter/material.dart';
import 'package:fitness_os/features/home/presentation/view/home_route.dart';
import 'app_router.dart';

/// Central place to register all feature routes
class RouteRegistry {
  static void registerAll() {
    // Default entry point — replace by registering a feature route at '/'
    AppRouter.register(
      '/',
      (context) => const Scaffold(
        body: Center(child: Text('App Initialized')),
      ),
    );

        HomeRoute.register();
    // [routes]
  }
}