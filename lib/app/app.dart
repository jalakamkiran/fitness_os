import 'package:flutter/material.dart';
import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:fitness_os/app/auto_sync_lifecycle.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';

class FitnessOsApp extends StatelessWidget {
  const FitnessOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AutoSyncLifecycle(
      autoSync: sl<OneShotAutoSync>(),
      link: sl<HuaweiLink>(),
      child: MaterialApp(
        theme: BpTheme.light(),
        darkTheme: BpTheme.dark(),
        initialRoute: '/',
        routes: AppRouter.routes,
      ),
    );
  }
}
