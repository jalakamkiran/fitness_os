import 'package:flutter/material.dart';

/// Central route registry
class AppRouter {
  static final Map<String, WidgetBuilder> routes = {};

  /// Register new feature routes
  static void register(String path, WidgetBuilder builder) {
    routes[path] = builder;
  }
}