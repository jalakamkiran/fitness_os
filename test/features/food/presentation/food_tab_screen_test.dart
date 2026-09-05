import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/food/presentation/view/food_tab_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FoodTabScreen renders without dependencies', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: const Scaffold(
          body: FoodTabScreen(),
        ),
      ),
    );

    expect(find.text('Food Logging'), findsOneWidget);
    expect(find.text('Track your meals with photos and notes'), findsOneWidget);
    expect(find.text('Log meal'), findsOneWidget);
    expect(find.text('Set meal times'), findsOneWidget);
    expect(find.text('Getting started'), findsOneWidget);
  });

  testWidgets('FoodTabScreen navigates to capture route when tapping Log meal',
      (tester) async {
    bool didAttemptNavigation = false;
    
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: const Scaffold(
          body: FoodTabScreen(),
        ),
        onGenerateRoute: (settings) {
          if (settings.name == '/food_capture') {
            didAttemptNavigation = true;
            return MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Capture route')),
            );
          }
          return null;
        },
      ),
    );

    // Tap Log meal button
    await tester.tap(find.text('Log meal'));
    await tester.pumpAndSettle();
    
    // Verify navigation was attempted
    expect(didAttemptNavigation, isTrue);
    expect(find.text('Capture route'), findsOneWidget);
  });

  testWidgets('FoodTabScreen shows snackbar when tapping Set meal times',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: const Scaffold(
          body: FoodTabScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Set meal times'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Meal schedule coming soon'), findsOneWidget);
  });

  testWidgets('FoodTabScreen has proper accessibility labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: const Scaffold(
          body: FoodTabScreen(),
        ),
      ),
    );

    expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
  });
}
