import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/app/shell/app_shell.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_bloc.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_route.dart';
import 'package:fitness_os/app/routing/app_router.dart';

class _FakeLink extends HuaweiLink {
  @override
  Future<void> start() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.I.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    sl.registerSingleton<SharedPreferences>(prefs);
    sl.registerSingleton<HuaweiLink>(_FakeLink());
    sl.registerLazySingleton<DevicePairingRepository>(
      () => DevicePairingRepositoryImpl(link: sl(), prefs: sl()),
    );
    sl.registerFactory(() => DevicePairingBloc(repository: sl()));
    AppRouter.routes.clear();
    WorkoutHistoryRoute.register();
  });

  tearDown(() async {
    await GetIt.I.reset();
    AppRouter.routes.clear();
  });

  testWidgets('cold start shows Home + Vitals nav; Home is pairing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const AppShell(),
        routes: AppRouter.routes,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Vitals'), findsOneWidget);
    expect(find.text('GT5 pairing'), findsOneWidget);
    expect(find.text('Scan GT5'), findsOneWidget);

    // Only two destinations.
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(2));
  });

  testWidgets('switching tabs preserves Home state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppShell()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vitals'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sleep and whole-day'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('GT5 pairing'), findsOneWidget);
    expect(find.text('Scan GT5'), findsOneWidget);
  });

  testWidgets('Workouts push from Home pops back to Home tab', (tester) async {
    AppRouter.register(
      '/workout_history',
      (_) => Scaffold(
        appBar: AppBar(title: const Text('Workouts stub')),
        body: const SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: const AppShell(),
        routes: AppRouter.routes,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Workouts').first);
    await tester.pumpAndSettle();
    expect(find.text('Workouts stub'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('GT5 pairing'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Home embed has single NavigationBar (no double bottom chrome)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppShell()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
