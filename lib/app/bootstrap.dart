import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'app.dart';
import 'routing/route_registry.dart';
import '../core/di/injector.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
  );

  /// Initialize dependency injection
  await initDependencies();

  /// Register all routes
  RouteRegistry.registerAll();

  runApp(const FitnessOsApp());
}
