import 'package:flutter/material.dart';
import 'app.dart';
import 'routing/route_registry.dart';
import '../core/di/injector.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// Initialize dependency injection
  await initDependencies();

  /// Register all routes
  RouteRegistry.registerAll();

  runApp(const FitnessOsApp());
}