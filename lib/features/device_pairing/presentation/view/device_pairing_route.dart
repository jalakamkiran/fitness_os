import 'package:flutter/material.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/device_pairing/presentation/view/device_pairing_screen.dart';

class DevicePairingRoute {
  static const String path = '/device_pairing';

  static void register() {
    // Home is pairing for Gate A cut.
    AppRouter.register(
      '/',
      (context) => const DevicePairingScreen(),
    );
    AppRouter.register(
      path,
      (context) => const DevicePairingScreen(),
    );
  }

  static void go(BuildContext context) {
    Navigator.pushNamed(context, path);
  }
}
