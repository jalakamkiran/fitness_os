import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/food/domain/daily_food_totals.dart';
import 'package:fitness_os/features/food/domain/food_meal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Concrete store for meal metadata + side-file photos.
///
/// Layout: `{appSupport}/food/meals/{dayKey}/{mealId}.jpg` + lean index in SharedPreferences.
/// Save integrity: write JPEG to temp in same dir → rename to final → commit index.
/// Startup orphan sweep: delete unreferenced files; drop index rows whose file is missing.
class FoodMealStore {
  FoodMealStore({
    required SharedPreferences prefs,
    Directory? Function()? rootOverride,
  })  : _prefs = prefs,
        _rootOverride = rootOverride;

  final SharedPreferences _prefs;
  final Directory? Function()? _rootOverride;

  /// Load all meals from index, sweeping orphans and invalid entries.
  Future<List<FoodMeal>> loadAll() async {
    final raw = _prefs.getString(GateAPrefs.foodMealsIndexJson);
    if (raw == null || raw.isEmpty) return const [];

    List<FoodMeal> meals;
    try {
      final decoded = jsonDecode(raw) as List;
      meals = decoded
          .cast<Map<String, dynamic>>()
          .map(FoodMeal.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }

    // Sweep: drop meals whose photo file is missing
    final root = await _mealsRoot();
    final valid = <FoodMeal>[];
    for (final meal in meals) {
      final file = File('${root.path}/${meal.photoPath}');
      if (await file.exists()) {
        valid.add(meal);
      }
    }

    if (valid.length != meals.length) {
      // Persist cleaned index
      await _saveIndex(valid);
    }

    // Sweep: delete unreferenced files under food/meals
    await _deleteOrphans(valid);

    return valid;
  }

  /// Load meals for a specific day.
  Future<List<FoodMeal>> loadDay(String dayKey) async {
    final all = await loadAll();
    return all.where((m) => m.dayKey == dayKey).toList();
  }

  /// Load daily totals helper.
  Future<DailyFoodTotals> loadDayTotals(String dayKey) async {
    final meals = await loadDay(dayKey);
    return DailyFoodTotals(dayKey: dayKey, meals: meals);
  }

  /// Save a new meal with photo bytes.
  ///
  /// Integrity: write photo to temp → rename → commit index.
  Future<void> save(FoodMeal meal, List<int> photoBytes) async {
    final all = List<FoodMeal>.from(await loadAll());

    // Write photo to temp file in meal dir, then rename
    final root = await _mealsRoot();
    final dayDir = Directory('${root.path}/${GateAPrefs.foodMealsDir}/${meal.dayKey}');
    if (!await dayDir.exists()) {
      await dayDir.create(recursive: true);
    }

    final finalPath = '${dayDir.path}/${meal.id}.jpg';
    final tempPath = '$finalPath.tmp';
    final tempFile = File(tempPath);

    try {
      await tempFile.writeAsBytes(photoBytes);
      await tempFile.rename(finalPath);
    } catch (e) {
      // Cleanup on failure
      try {
        if (await tempFile.exists()) await tempFile.delete();
        if (await File(finalPath).exists()) await File(finalPath).delete();
      } catch (_) {}
      rethrow;
    }

    // Commit to index only after photo is stable
    all.add(meal);
    await _saveIndex(all);
  }

  /// Update an existing meal (e.g., edit metadata).
  Future<void> update(FoodMeal meal) async {
    final all = List<FoodMeal>.from(await loadAll());
    final index = all.indexWhere((m) => m.id == meal.id);
    if (index == -1) return;

    all[index] = meal;
    await _saveIndex(all);
  }

  /// Replace a meal's photo with new bytes (e.g., user replaces image).
  ///
  /// Integrity: write new photo → update index → delete old photo.
  Future<void> replacePhoto(FoodMeal meal, List<int> newPhotoBytes) async {
    final all = List<FoodMeal>.from(await loadAll());
    final index = all.indexWhere((m) => m.id == meal.id);
    if (index == -1) return;

    final oldPhotoPath = all[index].photoPath;
    final root = await _mealsRoot();
    final oldFile = File('${root.path}/$oldPhotoPath');

    // Write new photo to temp
    final dayDir = Directory('${root.path}/${GateAPrefs.foodMealsDir}/${meal.dayKey}');
    if (!await dayDir.exists()) {
      await dayDir.create(recursive: true);
    }

    final finalPath = '${dayDir.path}/${meal.id}.jpg';
    final tempPath = '$finalPath.tmp';
    final tempFile = File(tempPath);

    try {
      await tempFile.writeAsBytes(newPhotoBytes);
      await tempFile.rename(finalPath);
    } catch (e) {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      rethrow;
    }

    // Update index
    all[index] = meal;
    await _saveIndex(all);

    // Delete old photo if different
    try {
      if (oldFile.path != finalPath && await oldFile.exists()) {
        await oldFile.delete();
      }
    } catch (_) {}
  }

  /// Delete a meal and its photo.
  Future<void> delete(String mealId) async {
    final all = List<FoodMeal>.from(await loadAll());
    final meal = all.firstWhere((m) => m.id == mealId, orElse: () => throw ArgumentError('Meal not found: $mealId'));

    // Delete photo file
    final root = await _mealsRoot();
    final file = File('${root.path}/${meal.photoPath}');
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    // Remove from index
    all.removeWhere((m) => m.id == mealId);
    await _saveIndex(all);

    // Prune empty day dirs
    await _pruneEmptyDayDirs();
  }

  /// Clear all meals (prefs + files). Used by Forget wipe.
  Future<void> clearLocal() async {
    await _prefs.remove(GateAPrefs.foodMealsIndexJson);

    // Delete meal dirs
    final root = await _mealsRoot();
    final mealsDir = Directory('${root.path}/${GateAPrefs.foodMealsDir}');
    try {
      if (await mealsDir.exists()) {
        await mealsDir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort wipe
    }
  }

  Future<void> _saveIndex(List<FoodMeal> meals) async {
    final json = jsonEncode(meals.map((m) => m.toJson()).toList());
    await _prefs.setString(GateAPrefs.foodMealsIndexJson, json);
  }

  Future<Directory> _mealsRoot() async {
    final override = _rootOverride?.call();
    final root = override ?? await getApplicationSupportDirectory();
    return root;
  }

  /// Delete unreferenced files under food/meals.
  Future<void> _deleteOrphans(List<FoodMeal> validMeals) async {
    final root = await _mealsRoot();
    final mealsDir = Directory('${root.path}/${GateAPrefs.foodMealsDir}');
    if (!await mealsDir.exists()) return;

    final validPaths = validMeals.map((m) => '${root.path}/${m.photoPath}').toSet();

    await for (final entity in mealsDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.jpg')) {
        if (!validPaths.contains(entity.path)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }

    // Prune empty day dirs
    await _pruneEmptyDayDirs();
  }

  Future<void> _pruneEmptyDayDirs() async {
    final root = await _mealsRoot();
    final mealsDir = Directory('${root.path}/${GateAPrefs.foodMealsDir}');
    if (!await mealsDir.exists()) return;

    await for (final entity in mealsDir.list()) {
      if (entity is Directory) {
        try {
          final isEmpty = await entity.list().isEmpty;
          if (isEmpty) {
            await entity.delete();
          }
        } catch (_) {}
      }
    }
  }
}
