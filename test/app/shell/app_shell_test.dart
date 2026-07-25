import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/app/shell/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('Home tab is not the pairing dashboard', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(
          homeBody: Scaffold(body: Text('HOME_NOW')),
          vitalsBody: Scaffold(body: Text('VITALS_BODY')),
          workoutsBody: Scaffold(body: Text('WORKOUTS_BODY')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HOME_NOW'), findsOneWidget);
    expect(find.text('GT5 pairing'), findsNothing);
    expect(find.text('Scan GT5'), findsNothing);
  });
}
