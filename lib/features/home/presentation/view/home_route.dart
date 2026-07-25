import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/home/presentation/view/home_screen.dart';

class HomeRoute {
  static const path = '/home';

  static void register() {
    AppRouter.register(
      path,
      (context) => const HomeScreen(),
    );
  }

  static void go(BuildContext context) {
    Navigator.pushNamed(context, path);
  }
}