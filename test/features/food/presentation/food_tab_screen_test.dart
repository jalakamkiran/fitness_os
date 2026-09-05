import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/presentation/view/food_tab_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FoodTabScreen basic functionality', () {
    late FoodMealStore store;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tempDir = await Directory.systemTemp.createTemp('food_tab_screen');
      store = FoodMealStore(prefs: prefs, rootOverride: () => tempDir);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('FoodTabScreen renders empty state without meals', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BpTheme.light(),
          home: Scaffold(
            body: FoodTabScreen(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No meals logged'), findsOneWidget);
      expect(find.text('Start tracking your meals with photos'), findsOneWidget);
      expect(find.text('Log meal'), findsOneWidget);
      expect(find.text('Set meal times'), findsOneWidget);
    });

    testWidgets('FoodTabScreen shows today navigation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BpTheme.light(),
          home: Scaffold(
            body: FoodTabScreen(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('FoodTabScreen navigates to capture route when tapping Log meal',
        (tester) async {
      bool didAttemptNavigation = false;
      
      await tester.pumpWidget(
        MaterialApp(
          theme: BpTheme.light(),
          home: Scaffold(
            body: FoodTabScreen(store: store),
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
      await tester.pumpAndSettle();

      // Tap Log meal button
      await tester.tap(find.text('Log meal'));
      await tester.pumpAndSettle();
      
      // Verify navigation was attempted
      expect(didAttemptNavigation, isTrue);
    });

    testWidgets('FoodTabScreen shows snackbar when tapping Set meal times',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BpTheme.light(),
          home: Scaffold(
            body: FoodTabScreen(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set meal times'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Meal schedule coming soon'), findsOneWidget);
    });

    testWidgets('FoodTabScreen has proper accessibility icons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BpTheme.light(),
          home: Scaffold(
            body: FoodTabScreen(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
      expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    });
  });
}

