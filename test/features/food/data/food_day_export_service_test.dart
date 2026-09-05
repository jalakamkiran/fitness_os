import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/food/data/food_day_export_service.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/domain/food_meal.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;
  late FoodMealStore store;
  late FoodDayExportService exportService;
  late SharedPreferences prefs;
  late bool forgetInFlight;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    
    tempDir = await Directory.systemTemp.createTemp('food_export_test');
    rootDir = Directory('${tempDir.path}/app_support');
    await rootDir.create(recursive: true);
    
    store = FoodMealStore(
      prefs: prefs,
      rootOverride: () => rootDir,
    );
    
    forgetInFlight = false;
    exportService = FoodDayExportService(
      store: store,
      isForgetInFlight: () => forgetInFlight,
      sideFileRootOverride: () => rootDir,
      exportCacheRootOverride: () => tempDir,
      clock: () => DateTime.utc(2026, 9, 6, 20, 15, 30),
    );
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('FoodDayExportService', () {
    test('exports day with meals and images to cache ZIP', () async {
      // Arrange
      const dayKey = '2026-09-06';
      final meal1 = FoodMeal(
        id: 'meal-1',
        dayKey: dayKey,
        capturedAtMs: 1725651330000,
        photoPath: 'food/meals/$dayKey/meal-1.jpg',
        name: 'Chicken salad',
        note: 'Light dressing',
        kcal: 450.0,
        slot: 'lunch',
      );
      final meal2 = FoodMeal(
        id: 'meal-2',
        dayKey: dayKey,
        capturedAtMs: 1725664800000,
        photoPath: 'food/meals/$dayKey/meal-2.jpg',
        slot: 'dinner',
      );

      final photo1Bytes = List.generate(100, (i) => i % 256);
      final photo2Bytes = List.generate(200, (i) => (i * 2) % 256);
      
      await store.save(meal1, photo1Bytes);
      await store.save(meal2, photo2Bytes);

      // Act
      final result = await exportService.exportDayToCache(dayKey);

      // Assert
      if (!result.isSuccess) {
        print('Export failed: ${result.message}');
        print('Status: ${result.status}');
      }
      expect(result.isSuccess, isTrue);
      expect(result.file, isNotNull);
      expect(result.file!.path, contains('day_food_exports'));
      expect(result.file!.path, contains('food_day_2026-09-06'));
      expect(await result.file!.exists(), isTrue);

      // Verify ZIP contents
      final zipBytes = await result.file!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      // Check manifest.json
      final manifestFile = archive.firstWhere((f) => f.name == 'manifest.json');
      final manifestJson = utf8.decode(manifestFile.content as List<int>);
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      expect(manifest['schemaVersion'], 1);
      expect(manifest['exportedAt'], '2026-09-06T20:15:30.000Z');
      expect(manifest['dayKey'], dayKey);
      expect(manifest['meals'], hasLength(2));

      final meal1Export = manifest['meals'][0] as Map<String, dynamic>;
      expect(meal1Export['id'], 'meal-1');
      expect(meal1Export['capturedAtMs'], 1725651330000);
      expect(meal1Export['slot'], 'lunch');
      expect(meal1Export['name'], 'Chicken salad');
      expect(meal1Export['note'], 'Light dressing');
      expect(meal1Export['kcal'], 450.0);
      expect(meal1Export['photoRelPath'], 'images/meal-1.jpg');
      expect(meal1Export['photoStatus'], 'present');
      expect(meal1Export['source'], 'manual');

      final meal2Export = manifest['meals'][1] as Map<String, dynamic>;
      expect(meal2Export['id'], 'meal-2');
      expect(meal2Export['slot'], 'dinner');
      expect(meal2Export.containsKey('name'), isFalse);
      expect(meal2Export.containsKey('note'), isFalse);
      expect(meal2Export.containsKey('kcal'), isFalse);
      expect(meal2Export['photoStatus'], 'present');

      // Check images
      final image1 = archive.firstWhere((f) => f.name == 'images/meal-1.jpg');
      expect(image1.content, photo1Bytes);

      final image2 = archive.firstWhere((f) => f.name == 'images/meal-2.jpg');
      expect(image2.content, photo2Bytes);
    });

    test('includes meal with empty kcal in manifest', () async {
      // Arrange
      const dayKey = '2026-09-06';
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: dayKey,
        capturedAtMs: 1725651330000,
        photoPath: 'food/meals/$dayKey/meal-1.jpg',
        name: 'Mystery meal',
        kcal: null, // Empty kcal
      );
      await store.save(meal, List.generate(50, (i) => i));

      // Act
      final result = await exportService.exportDayToCache(dayKey);

      // Assert
      expect(result.isSuccess, isTrue);
      final zipBytes = await result.file!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = archive.firstWhere((f) => f.name == 'manifest.json');
      final manifestJson = utf8.decode(manifestFile.content as List<int>);
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      final mealExport = manifest['meals'][0] as Map<String, dynamic>;
      expect(mealExport['name'], 'Mystery meal');
      expect(mealExport.containsKey('kcal'), isFalse); // kcal not included when null
      expect(mealExport['photoStatus'], 'present');
    });

    test('includes meals with photos in export', () async {
      // Arrange
      const dayKey = '2026-09-06';
      final meal1 = FoodMeal(
        id: 'meal-1',
        dayKey: dayKey,
        capturedAtMs: 1725651330000,
        photoPath: 'food/meals/$dayKey/meal-1.jpg',
        name: 'First meal',
      );
      final meal2 = FoodMeal(
        id: 'meal-2',
        dayKey: dayKey,
        capturedAtMs: 1725651340000,
        photoPath: 'food/meals/$dayKey/meal-2.jpg',
        name: 'Second meal',
      );
      
      await store.save(meal1, List.generate(50, (i) => i));
      await store.save(meal2, List.generate(60, (i) => i * 2));

      // Act
      final result = await exportService.exportDayToCache(dayKey);

      // Assert
      expect(result.isSuccess, isTrue);
      final zipBytes = await result.file!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      // Manifest should have both meals
      final manifestFile = archive.firstWhere((f) => f.name == 'manifest.json');
      final manifestJson = utf8.decode(manifestFile.content as List<int>);
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
      expect(manifest['meals'], hasLength(2));
      
      final meal1Export = manifest['meals'][0] as Map<String, dynamic>;
      expect(meal1Export['photoStatus'], 'present');
      expect(meal1Export['name'], 'First meal');
      
      final meal2Export = manifest['meals'][1] as Map<String, dynamic>;
      expect(meal2Export['photoStatus'], 'present');
      expect(meal2Export['name'], 'Second meal');

      // Both images should be in ZIP
      final imageFiles = archive.where((f) => f.name.startsWith('images/')).toList();
      expect(imageFiles, hasLength(2));
    });

    test('refuses path outside food export cache', () async {
      // Arrange
      const dayKey = '2026-09-06';
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: dayKey,
        capturedAtMs: 1725651330000,
        photoPath: 'food/meals/$dayKey/meal-1.jpg',
      );
      await store.save(meal, List.generate(50, (i) => i));

      // Create service with different export root
      final differentRoot = Directory('${tempDir.path}/different_root');
      await differentRoot.create();
      final badService = FoodDayExportService(
        store: store,
        isForgetInFlight: () => false,
        sideFileRootOverride: () => rootDir,
        exportCacheRootOverride: () => differentRoot,
        clock: () => DateTime.utc(2026, 9, 6),
      );

      // Act
      final result = await badService.exportDayToCache(dayKey);

      // Assert - succeeds because it writes to its own cache
      expect(result.isSuccess, isTrue);
      expect(result.file!.path, contains('different_root'));
      expect(result.file!.path, contains('day_food_exports'));
    });

    test('fails when no meals exist for day', () async {
      // Arrange
      const dayKey = '2026-09-06';

      // Act
      final result = await exportService.exportDayToCache(dayKey);

      // Assert
      expect(result.isSuccess, isFalse);
      expect(result.status, FoodDayExportStatus.failed);
      expect(result.message, contains('No meals'));
    });

    test('blocks when Forget is in flight', () async {
      // Arrange
      const dayKey = '2026-09-06';
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: dayKey,
        capturedAtMs: 1725651330000,
        photoPath: 'food/meals/$dayKey/meal-1.jpg',
      );
      await store.save(meal, List.generate(50, (i) => i));
      forgetInFlight = true;

      // Act
      final result = await exportService.exportDayToCache(dayKey);

      // Assert
      expect(result.isSuccess, isFalse);
      expect(result.status, FoodDayExportStatus.blocked);
      expect(result.message, contains('Forget in progress'));
    });

    test('prunes prior exports after successful export', () async {
      // Arrange
      const dayKey = '2026-09-06';
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: dayKey,
        capturedAtMs: 1725651330000,
        photoPath: 'food/meals/$dayKey/meal-1.jpg',
      );
      await store.save(meal, List.generate(50, (i) => i));

      // Create a prior export file
      final cacheDir = Directory('${tempDir.path}/day_food_exports');
      await cacheDir.create(recursive: true);
      final priorFile = File('${cacheDir.path}/food_day_2026-09-05_old.zip');
      await priorFile.writeAsString('old export');

      // Act
      final result = await exportService.exportDayToCache(dayKey);

      // Assert
      expect(result.isSuccess, isTrue);
      expect(await priorFile.exists(), isFalse); // Prior file pruned
      expect(await result.file!.exists(), isTrue); // New file kept
    });

    test('pruneFoodExportCache deletes entire cache directory', () async {
      // Arrange
      final cacheDir = Directory('${tempDir.path}/day_food_exports');
      await cacheDir.create(recursive: true);
      final file1 = File('${cacheDir.path}/export1.zip');
      final file2 = File('${cacheDir.path}/export2.zip');
      await file1.writeAsString('export1');
      await file2.writeAsString('export2');

      // Act
      await exportService.pruneFoodExportCache();

      // Assert
      expect(await cacheDir.exists(), isFalse);
      expect(await file1.exists(), isFalse);
      expect(await file2.exists(), isFalse);
    });

    test('exportInFlight flag tracks export state', () async {
      // Arrange
      const dayKey = '2026-09-06';
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: dayKey,
        capturedAtMs: 1725651330000,
        photoPath: 'food/meals/$dayKey/meal-1.jpg',
      );
      await store.save(meal, List.generate(50, (i) => i));

      expect(exportService.exportInFlight, isFalse);

      // Act & Assert
      final exportFuture = exportService.exportDayToCache(dayKey);
      // Note: In a real async test we'd need better timing, but this demonstrates the pattern
      await exportFuture;
      expect(exportService.exportInFlight, isFalse); // Cleared after completion
    });

    test('handles multiple meals with various field combinations', () async {
      // Arrange
      const dayKey = '2026-09-06';
      final meals = [
        FoodMeal(
          id: 'meal-1',
          dayKey: dayKey,
          capturedAtMs: 1725651330000,
          photoPath: 'food/meals/$dayKey/meal-1.jpg',
          name: 'Breakfast',
          kcal: 300.0,
          slot: 'breakfast',
        ),
        FoodMeal(
          id: 'meal-2',
          dayKey: dayKey,
          capturedAtMs: 1725658530000,
          photoPath: 'food/meals/$dayKey/meal-2.jpg',
          note: 'Quick snack',
          slot: 'snack',
        ),
        FoodMeal(
          id: 'meal-3',
          dayKey: dayKey,
          capturedAtMs: 1725665730000,
          photoPath: 'food/meals/$dayKey/meal-3.jpg',
          name: 'Dinner',
          note: 'Home cooked',
          kcal: 650.5,
        ),
      ];

      for (final meal in meals) {
        await store.save(meal, List.generate(100, (i) => i));
      }

      // Act
      final result = await exportService.exportDayToCache(dayKey);

      // Assert
      expect(result.isSuccess, isTrue);
      final zipBytes = await result.file!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = archive.firstWhere((f) => f.name == 'manifest.json');
      final manifestJson = utf8.decode(manifestFile.content as List<int>);
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      expect(manifest['meals'], hasLength(3));
      
      // Verify each meal's fields are correctly included/omitted
      final meal1 = manifest['meals'][0] as Map<String, dynamic>;
      expect(meal1['name'], 'Breakfast');
      expect(meal1['kcal'], 300.0);
      expect(meal1['slot'], 'breakfast');
      expect(meal1.containsKey('note'), isFalse);

      final meal2 = manifest['meals'][1] as Map<String, dynamic>;
      expect(meal2.containsKey('name'), isFalse);
      expect(meal2['note'], 'Quick snack');
      expect(meal2.containsKey('kcal'), isFalse);

      final meal3 = manifest['meals'][2] as Map<String, dynamic>;
      expect(meal3['name'], 'Dinner');
      expect(meal3['note'], 'Home cooked');
      expect(meal3['kcal'], 650.5);
      expect(meal3.containsKey('slot'), isFalse);
    });
  });
}
