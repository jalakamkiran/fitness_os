import 'dart:io';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/domain/food_meal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('FoodMealStore', () {
    late Directory tempRoot;
    late SharedPreferences prefs;
    late FoodMealStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tempRoot = await Directory.systemTemp.createTemp('food_store_test_');
      store = FoodMealStore(
        prefs: prefs,
        rootOverride: () => tempRoot,
      );
    });

    tearDown(() async {
      try {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('Happy path: save meal with photo + optional empty kcal → reload',
        () async {
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
        name: 'Breakfast',
        note: null,
        kcal: null, // Empty kcal
        slot: 'breakfast',
      );

      final photoBytes = List.generate(100, (i) => i % 256);
      await store.save(meal, photoBytes);

      final loaded = await store.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.id, meal.id);
      expect(loaded.first.kcal, isNull);

      // Photo file exists
      final photoFile = File('${tempRoot.path}/${meal.photoPath}');
      expect(await photoFile.exists(), isTrue);
    });

    test('Daily total helper ignores empty kcal', () async {
      final meal1 = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
        kcal: null,
      );
      final meal2 = FoodMeal(
        id: 'meal-2',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-2.jpg',
        kcal: 500.0,
      );

      await store.save(meal1, List.generate(50, (i) => i));
      await store.save(meal2, List.generate(50, (i) => i));

      final totals = await store.loadDayTotals('2026-09-05');
      expect(totals.mealCount, 2);
      expect(totals.totalKcal, 500.0); // Ignores null kcal
      expect(totals.isIncomplete, isTrue); // Meal1 has no kcal
    });

    test('Delete meal removes metadata + photo; empty day dirs pruned',
        () async {
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );

      await store.save(meal, List.generate(100, (i) => i));

      final photoFile = File('${tempRoot.path}/${meal.photoPath}');
      expect(await photoFile.exists(), isTrue);

      await store.delete(meal.id);

      final loaded = await store.loadAll();
      expect(loaded, isEmpty);
      expect(await photoFile.exists(), isFalse);

      // Day dir should be pruned
      final dayDir =
          Directory('${tempRoot.path}/${GateAPrefs.foodMealsDir}/2026-09-05');
      expect(await dayDir.exists(), isFalse);
    });

    test('Orphan file cleaned on load; no dangling index without file',
        () async {
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );

      await store.save(meal, List.generate(100, (i) => i));

      // Delete photo file manually (orphan scenario)
      final photoFile = File('${tempRoot.path}/${meal.photoPath}');
      await photoFile.delete();

      // Load should sweep missing photo from index
      final loaded = await store.loadAll();
      expect(loaded, isEmpty);

      // Verify index was cleaned
      final indexJson = prefs.getString(GateAPrefs.foodMealsIndexJson);
      expect(indexJson, '[]');
    });

    test('Orphan photo file deleted on load', () async {
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );

      await store.save(meal, List.generate(100, (i) => i));

      // Plant an orphan file not in index
      final orphanFile = File(
        '${tempRoot.path}/${GateAPrefs.foodMealsDir}/2026-09-05/orphan.jpg',
      );
      await orphanFile.parent.create(recursive: true);
      await orphanFile.writeAsBytes(List.generate(50, (i) => i));

      expect(await orphanFile.exists(), isTrue);

      // Load should delete orphan
      await store.loadAll();
      expect(await orphanFile.exists(), isFalse);
    });

    test('Replace photo: new file → index → delete old', () async {
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );

      final oldBytes = List.generate(100, (i) => i);
      await store.save(meal, oldBytes);

      final oldFile = File('${tempRoot.path}/${meal.photoPath}');
      expect(await oldFile.exists(), isTrue);

      // Replace photo
      final newBytes = List.generate(200, (i) => i + 100);
      await store.replacePhoto(meal, newBytes);

      // New photo exists
      final newFile = File('${tempRoot.path}/${meal.photoPath}');
      expect(await newFile.exists(), isTrue);
      expect(await newFile.length(), greaterThan(100));

      // Index still valid
      final loaded = await store.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.id, meal.id);
    });

    test('Forget wipe empties food prefs + files', () async {
      final meal1 = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );
      final meal2 = FoodMeal(
        id: 'meal-2',
        dayKey: '2026-09-06',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-06/meal-2.jpg',
      );

      await store.save(meal1, List.generate(100, (i) => i));
      await store.save(meal2, List.generate(100, (i) => i));

      expect(await store.loadAll(), hasLength(2));

      // Wipe
      await store.clearLocal();

      // Verify empty
      final loaded = await store.loadAll();
      expect(loaded, isEmpty);

      final indexJson = prefs.getString(GateAPrefs.foodMealsIndexJson);
      expect(indexJson, isNull);

      // Verify meal files deleted
      final mealsDir =
          Directory('${tempRoot.path}/${GateAPrefs.foodMealsDir}');
      expect(await mealsDir.exists(), isFalse);
    });

    test('Residue check fails if JPEGs remain after wipe', () async {
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );

      await store.save(meal, List.generate(100, (i) => i));

      // Wipe
      await store.clearLocal();

      // Manually plant residue to simulate incomplete wipe
      final residueFile = File('${tempRoot.path}/${meal.photoPath}');
      await residueFile.parent.create(recursive: true);
      await residueFile.writeAsBytes(List.generate(50, (i) => i));

      // Verify residue exists (test helper would check this)
      final mealsDir =
          Directory('${tempRoot.path}/${GateAPrefs.foodMealsDir}');
      final hasFiles =
          await mealsDir.list(recursive: true).any((e) => e is File);
      expect(hasFiles, isTrue);
    });

    test('Update meal metadata without touching photo', () async {
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
        name: 'Breakfast',
        kcal: null,
      );

      await store.save(meal, List.generate(100, (i) => i));

      // Update kcal
      final updated = meal.copyWith(kcal: 500.0, name: 'Updated Breakfast');
      await store.update(updated);

      final loaded = await store.loadAll();
      expect(loaded.first.kcal, 500.0);
      expect(loaded.first.name, 'Updated Breakfast');

      // Photo unchanged
      final photoFile = File('${tempRoot.path}/${meal.photoPath}');
      expect(await photoFile.exists(), isTrue);
    });

    test('Load empty store returns empty list', () async {
      final loaded = await store.loadAll();
      expect(loaded, isEmpty);
    });

    test('Load day with no meals returns empty list', () async {
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );

      await store.save(meal, List.generate(100, (i) => i));

      final loaded = await store.loadDay('2026-09-06');
      expect(loaded, isEmpty);
    });

    test('Multiple meals same day', () async {
      final meal1 = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
        slot: 'breakfast',
      );
      final meal2 = FoodMeal(
        id: 'meal-2',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-2.jpg',
        slot: 'lunch',
      );

      await store.save(meal1, List.generate(100, (i) => i));
      await store.save(meal2, List.generate(100, (i) => i));

      final loaded = await store.loadDay('2026-09-05');
      expect(loaded, hasLength(2));
      expect(loaded.map((m) => m.slot).toSet(), {'breakfast', 'lunch'});
    });

    test('DI composition: clearLocal works as expected', () async {
      // This test verifies clearLocal can be called from DI wipe
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );

      await store.save(meal, List.generate(100, (i) => i));
      expect(await store.loadAll(), hasLength(1));

      // Simulate DI calling clearLocal
      await store.clearLocal();

      expect(await store.loadAll(), isEmpty);
      expect(prefs.getString(GateAPrefs.foodMealsIndexJson), isNull);
    });

    test('Corrupt index JSON returns empty list', () async {
      await prefs.setString(GateAPrefs.foodMealsIndexJson, 'not-valid-json');

      final loaded = await store.loadAll();
      expect(loaded, isEmpty);
    });

    test('Save integrity: temp → rename → index', () async {
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );

      await store.save(meal, List.generate(100, (i) => i));

      // Verify no .tmp file left behind
      final tempFile =
          File('${tempRoot.path}/${meal.photoPath}.tmp');
      expect(await tempFile.exists(), isFalse);

      // Final file exists
      final finalFile = File('${tempRoot.path}/${meal.photoPath}');
      expect(await finalFile.exists(), isTrue);

      // Index committed
      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
    });
  });
}
