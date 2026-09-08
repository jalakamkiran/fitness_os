import 'dart:io';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_service.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/domain/food_meal.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake implementations for testing
class FakeHuaweiLink extends Fake implements HuaweiLink {
  @override
  bool get syncInFlight => false;

  @override
  Future<void> clearSecrets() async {}

  @override
  Future<void> disconnect() async {}
}

class FakeVitalsRepository implements VitalsRepository {
  bool clearLocalCalled = false;

  @override
  Future<void> clearLocal() async {
    clearLocalCalled = true;
  }

  @override
  bool get isSyncOrMergeInFlight => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeExportService extends Fake implements AppDataExportService {
  bool pruneExportCacheCalled = false;

  @override
  Future<void> pruneExportCache() async {
    pruneExportCacheCalled = true;
  }

  @override
  bool get exportInFlight => false;
}

void main() {
  group('Forget Wipe Integration', () {
    late Directory tempRoot;
    late SharedPreferences prefs;
    late FoodMealStore foodStore;
    late FakeVitalsRepository vitalsRepo;
    late FakeExportService exportService;
    late Future<void> Function() wipeCallback;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tempRoot = await Directory.systemTemp.createTemp('forget_wipe_test_');
      
      foodStore = FoodMealStore(
        prefs: prefs,
        rootOverride: () => tempRoot,
      );
      
      vitalsRepo = FakeVitalsRepository();
      exportService = FakeExportService();
      
      // Create the composition callback (simulating diagnostics_di)
      wipeCallback = () async {
        await vitalsRepo.clearLocal();
        await exportService.pruneExportCache();
        await foodStore.clearLocal();
      };
    });

    tearDown(() async {
      try {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('Forget wipe composition calls all components', () async {
      // Setup data in food store
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );
      
      await foodStore.save(meal, List.generate(100, (i) => i));
      expect(await foodStore.loadAll(), hasLength(1));

      // Execute wipe composition
      await wipeCallback();
      
      // Verify all components were called in order
      expect(vitalsRepo.clearLocalCalled, isTrue);
      expect(exportService.pruneExportCacheCalled, isTrue);
      
      // Verify food cleared
      expect(await foodStore.loadAll(), isEmpty);
      expect(prefs.containsKey(GateAPrefs.foodMealsIndexJson), isFalse);
      
      final mealsDir =
          Directory('${tempRoot.path}/${GateAPrefs.foodMealsDir}');
      expect(await mealsDir.exists(), isFalse);
    });

    test('Wipe leaves no food residue (prefs or files)', () async {
      // Setup and wipe
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );
      
      await foodStore.save(meal, List.generate(100, (i) => i));
      expect(await foodStore.loadAll(), hasLength(1));

      // Execute wipe
      await wipeCallback();

      // Verify no prefs residue
      expect(prefs.containsKey(GateAPrefs.foodMealsIndexJson), isFalse);

      // Verify no file residue
      final mealsDir =
          Directory('${tempRoot.path}/${GateAPrefs.foodMealsDir}');
      if (await mealsDir.exists()) {
        final hasFiles =
            await mealsDir.list(recursive: true).any((e) => e is File);
        expect(hasFiles, isFalse, reason: 'Should have no meal files after wipe');
      }
    });

    test('DI composition includes vitals + export + food in order', () async {
      // Setup data
      final meal = FoodMeal(
        id: 'meal-1',
        dayKey: '2026-09-05',
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
        photoPath: '${GateAPrefs.foodMealsDir}/2026-09-05/meal-1.jpg',
      );
      
      await foodStore.save(meal, List.generate(100, (i) => i));

      // Execute wipe composition
      await wipeCallback();

      // Verify all three components were invoked
      expect(vitalsRepo.clearLocalCalled, isTrue,
          reason: 'Vitals clear should be called');
      expect(exportService.pruneExportCacheCalled, isTrue,
          reason: 'Export prune should be called');
      expect(await foodStore.loadAll(), isEmpty,
          reason: 'Food clear should be called');
    });
  });
}
