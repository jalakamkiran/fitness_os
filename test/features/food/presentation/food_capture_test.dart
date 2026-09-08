import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/domain/food_meal.dart';
import 'package:fitness_os/features/food/presentation/view/food_capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('FoodCaptureScreen UI', () {
    late FoodMealStore store;
    late Directory tempDir;
    late File photoFile;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tempDir = await Directory.systemTemp.createTemp('food_capture_ui');
      store = FoodMealStore(prefs: prefs, rootOverride: () => tempDir);
      photoFile = File('${tempDir.path}/p.jpg');
      await photoFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Widget buildScreen({File? Function(ImageSource)? syncPick}) {
      return MaterialApp(
        home: FoodCaptureScreen(
          store: store,
          imagePicker: ImagePicker(),
          processImage: (_) async =>
              Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
          syncPickOverride: syncPick,
          imageBuilder: (_) => const Text('Preview'),
        ),
      );
    }

    testWidgets('shows photo placeholder and hides Save without photo',
        (tester) async {
      await tester.pumpWidget(buildScreen(syncPick: (_) => null));

      expect(find.text('Add a photo of your meal'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('sync pick enables Save', (tester) async {
      await tester.pumpWidget(buildScreen(syncPick: (_) => photoFile));

      await tester.tap(find.text('Camera'));
      await tester.pump();

      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('Food capture save contract (store)', () {
    late FoodMealStore store;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tempDir = await Directory.systemTemp.createTemp('food_capture_contract');
      store = FoodMealStore(prefs: prefs, rootOverride: () => tempDir);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('photo-only meal yields incomplete day total', () async {
      final today = DateTime.now();
      final dayKey =
          '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

      await store.save(
        FoodMeal(
          id: 'm0',
          dayKey: dayKey,
          capturedAtMs: today.millisecondsSinceEpoch,
          photoPath: 'food/meals/$dayKey/m0.jpg',
        ),
        bytes,
      );

      final totals = await store.loadDayTotals(dayKey);
      expect(totals.mealCount, 1);
      expect(totals.totalKcal, isNull);
      expect(totals.isIncomplete, isTrue);
    });

    test('optional kcal name note slot persist', () async {
      final today = DateTime.now();
      final dayKey =
          '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

      await store.save(
        FoodMeal(
          id: 'm1',
          dayKey: dayKey,
          capturedAtMs: today.millisecondsSinceEpoch,
          photoPath: 'food/meals/$dayKey/m1.jpg',
          name: 'Grilled salmon',
          note: 'Very tasty',
          kcal: 650,
          slot: 'dinner',
        ),
        bytes,
      );

      final meal = (await store.loadAll()).single;
      expect(meal.name, 'Grilled salmon');
      expect(meal.note, 'Very tasty');
      expect(meal.kcal, 650.0);
      expect(meal.slot, 'dinner');
    });
  });
}
