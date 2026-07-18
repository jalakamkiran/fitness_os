import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/device_pairing/presentation/view/device_pairing_screen.dart';

class DevicePairingRoute {
  static const String path = '/device_pairing';

  static void register() {
    // Shell owns `/`. Keep an explicit pairing route for deep links / tests.
    AppRouter.register(
      path,
      (context) => const DevicePairingScreen(),
    );
  }

  static void go(BuildContext context) {
    Navigator.pushNamed(context, path);
  }
}
