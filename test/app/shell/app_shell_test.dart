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
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';
import 'package:fitness_os/features/workout_history/presentation/bloc/workout_history_bloc.dart';
import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/app/routing/app_router.dart';

class _FakeLink extends HuaweiLink {
  @override
  Future<void> start() async {}
}

class _EmptyWorkoutsRepo implements WorkoutHistoryRepository {
  @override
  Future<bool> isGateAPassed() async => true;

  @override
  Future<List<WorkoutSummary>> loadLocal() async => const [];

  @override
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch() async =>
      const Right([]);
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
    sl.registerLazySingleton<WorkoutHistoryRepository>(_EmptyWorkoutsRepo.new);
    sl.registerFactory(
      () => WorkoutHistoryBloc(repository: sl()),
    );
    AppRouter.routes.clear();
  });

  tearDown(() async {
    await GetIt.I.reset();
    AppRouter.routes.clear();
  });

  testWidgets('three tabs labeled Home, Vitals, Workouts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(
          homeBody: Scaffold(body: Text('HOME_BODY')),
          vitalsBody: Scaffold(body: Text('VITALS_BODY')),
          workoutsBody: Scaffold(body: Text('WORKOUTS_BODY')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Vitals'), findsOneWidget);
    expect(find.text('Workouts'), findsOneWidget);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(3));
    expect(find.text('HOME_BODY'), findsOneWidget);

    await tester.tap(find.text('Vitals'));
    await tester.pumpAndSettle();
    expect(find.text('VITALS_BODY'), findsOneWidget);

    await tester.tap(find.text('Workouts'));
    await tester.pumpAndSettle();
    expect(find.text('WORKOUTS_BODY'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('HOME_BODY'), findsOneWidget);
  });

  testWidgets('cold start Home remains pairing until Home agent lands',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(
          vitalsBody: Scaffold(body: Text('VITALS_BODY')),
          workoutsBody: Scaffold(body: Text('WORKOUTS_BODY')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GT5 pairing'), findsOneWidget);
    expect(find.text('Scan GT5'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Home embed has single NavigationBar (no double bottom chrome)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(
          homeBody: Scaffold(body: Text('HOME_BODY')),
          vitalsBody: Scaffold(body: Text('VITALS_BODY')),
          workoutsBody: Scaffold(body: Text('WORKOUTS_BODY')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
