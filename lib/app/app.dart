import 'package:flutter/material.dart';
import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:fitness_os/app/auto_sync_lifecycle.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/app/splash/fathom_splash_screen.dart';
import 'package:fitness_os/app/splash/fathom_splash_timing.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';

class FitnessOsApp extends StatelessWidget {
  const FitnessOsApp({
    super.key,
    this.showSplash = true,
    this.splashTiming = FathomSplashTiming.standard,
  });

  /// Cold-start brand moment (Discobolus → T → Fathom). Disable in tests.
  final bool showSplash;

  final FathomSplashTiming splashTiming;

  @override
  Widget build(BuildContext context) {
    return AutoSyncLifecycle(
      autoSync: sl<OneShotAutoSync>(),
      link: sl<HuaweiLink>(),
      child: MaterialApp(
        title: 'Fathom',
        theme: BpTheme.light(),
        darkTheme: BpTheme.dark(),
        initialRoute: '/',
        routes: AppRouter.routes,
        builder: (context, child) {
          final content = child ?? const SizedBox.shrink();
          if (!showSplash) return content;
          return FathomSplashGate(
            timing: splashTiming,
            child: content,
          );
        },
      ),
    );
  }
}
