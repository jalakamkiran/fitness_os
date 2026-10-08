import 'package:flutter/material.dart';

/// Central route registry
class AppRouter {
  static final Map<String, WidgetBuilder> routes = {};

  /// Register new feature routes
  static void register(String path, WidgetBuilder builder) {
    routes[path] = builder;
  }

  /// Test seam — wipe registry between widget tests.
  @visibleForTesting
  static void clearForTest() => routes.clear();
}