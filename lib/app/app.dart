import 'package:flutter/material.dart';
import 'package:blueprint_ui/src/theme/bp_theme.dart';
import 'routing/app_router.dart';


class FitnessOsApp extends StatelessWidget {
  const FitnessOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: BpTheme.light(),
      darkTheme: BpTheme.dark(),
      initialRoute: '/',
      routes: AppRouter.routes,
    );
  }
}