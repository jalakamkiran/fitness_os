import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fitness_os/features/food/data/food_meal_store.dart';

/// Assembles / writes / prunes the owner-initiated day-food ZIP export.
///
/// ZIP contents: manifest.json + images/{mealId}.jpg copies.
/// Export cache: peer to app-data exports (e.g. temp/day_food_exports/).
class FoodDayExportService {
  FoodDayExportService({
    required FoodMealStore store,
    required bool Function() isForgetInFlight,
    Directory? Function()? sideFileRootOverride,
    Directory? Function()? exportCacheRootOverride,
    DateTime Function()? clock,
  })  : _store = store,
        _isForgetInFlight = isForgetInFlight,
        _sideFileRootOverride = sideFileRootOverride,
        _exportCacheRootOverride = exportCacheRootOverride,
        _clock = clock ?? DateTime.now;

  final FoodMealStore _store;
  final bool Function() _isForgetInFlight;
  final Directory? Function()? _sideFileRootOverride;
  final Directory? Function()? _exportCacheRootOverride;
  final DateTime Function() _clock;

  bool _exportInFlight = false;

  bool get exportInFlight => _exportInFlight;

  /// Assemble day meals + images into ZIP under export cache, prune prior files.
  Future<FoodDayExportResult> exportDayToCache(String dayKey) async {
    if (_isForgetInFlight()) {
      return const FoodDayExportResult.blocked('Export blocked — Forget in progress');
    }
    
    _exportInFlight = true;
    try {
      final meals = await _store.loadDay(dayKey);
      if (meals.isEmpty) {
        return const FoodDayExportResult.failed('No meals to export for this day');
      }

      // Re-check Forget immediately before write (ignore self flag).
      if (_isForgetInFlight()) {
        return const FoodDayExportResult.blocked(
          'Export blocked — Forget started during assemble',
        );
      }

      final file = await _assembleZip(dayKey, meals);
      await _prunePriorExports(keep: file);

      if (!_isUnderExportCache(file)) {
        try {
          await file.delete();
        } catch (_) {}
        return const FoodDayExportResult.failed(
          'Export path escaped cache — refused',
        );
      }

      return FoodDayExportResult.success(
        file: file,
        byteLength: await file.length(),
      );
    } on FileSystemException catch (e) {
      return FoodDayExportResult.failed('Export write failed — ${e.message}');
    } catch (e) {
      return FoodDayExportResult.failed('Export failed — $e');
    } finally {
      _exportInFlight = false;
    }
  }

  /// Removes food export cache (Forget wipe).
  Future<void> pruneFoodExportCache() async {
    try {
      final dir = await _exportCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort prune.
    }
  }

  Future<File> _assembleZip(String dayKey, List<dynamic> meals) async {
    final archive = Archive();

    // Build manifest
    final mealsList = <Map<String, dynamic>>[];
    final manifest = {
      'schemaVersion': 1,
      'exportedAt': _clock().toUtc().toIso8601String(),
      'dayKey': dayKey,
      'meals': mealsList,
    };

    final rootDir = await _sideFileRoot();

    // Add meals and their images
    for (final meal in meals) {
      final mealMap = meal.toJson() as Map<String, dynamic>;
      final photoPath = meal.photoPath as String;
      final mealId = meal.id as String;

      final photoFile = File('${rootDir.path}/$photoPath');
      String photoStatus;

      if (await photoFile.exists()) {
        try {
          final photoBytes = await photoFile.readAsBytes();
          final imageFile = ArchiveFile(
            'images/$mealId.jpg',
            photoBytes.length,
            photoBytes,
          );
          archive.addFile(imageFile);
          photoStatus = 'present';
        } catch (_) {
          photoStatus = 'corrupt';
        }
      } else {
        photoStatus = 'absent';
      }

      mealsList.add({
        'id': mealMap['id'],
        'capturedAtMs': mealMap['capturedAtMs'],
        if (mealMap['slot'] != null) 'slot': mealMap['slot'],
        if (mealMap['name'] != null) 'name': mealMap['name'],
        if (mealMap['note'] != null) 'note': mealMap['note'],
        if (mealMap['kcal'] != null) 'kcal': mealMap['kcal'],
        'photoRelPath': 'images/$mealId.jpg',
        'photoStatus': photoStatus,
        'source': 'manual',
      });
    }

    // Add manifest.json
    final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);
    final manifestFile = ArchiveFile(
      'manifest.json',
      manifestJson.length,
      manifestJson.codeUnits,
    );
    archive.addFile(manifestFile);

    // Write ZIP
    final dir = await _exportCacheDir();
    final stamp = _clock().toUtc();
    final y = stamp.year.toString().padLeft(4, '0');
    final m = stamp.month.toString().padLeft(2, '0');
    final d = stamp.day.toString().padLeft(2, '0');
    final hh = stamp.hour.toString().padLeft(2, '0');
    final mm = stamp.minute.toString().padLeft(2, '0');
    final ss = stamp.second.toString().padLeft(2, '0');
    final name = 'food_day_${dayKey}_$y$m${d}_$hh$mm$ss.zip';
    final file = File('${dir.path}/$name');

    final encoder = ZipEncoder();
    final bytes = encoder.encode(archive);
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else {
      throw Exception('Failed to encode ZIP');
    }

    return file;
  }

  Future<Directory> _sideFileRoot() async {
    final override = _sideFileRootOverride?.call();
    if (override != null) return override;
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      rethrow;
    }
  }

  Future<Directory> _exportCacheDir() async {
    final override = _exportCacheRootOverride?.call();
    final root = override ?? await getTemporaryDirectory();
    final dir = Directory('${root.path}/$_exportCacheDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _prunePriorExports({required File keep}) async {
    final dir = await _exportCacheDir();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (entity.path == keep.path) continue;
      if (!entity.path.endsWith('.zip')) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  bool _isUnderExportCache(File file) {
    final path = file.absolute.path;
    final override = _exportCacheRootOverride?.call();
    if (override != null) {
      final cache = '${override.absolute.path}/$_exportCacheDirName';
      return path == cache || path.startsWith('$cache/');
    }
    final marker = '/$_exportCacheDirName/';
    return path.contains(marker);
  }

  static const _exportCacheDirName = 'day_food_exports';
  static const softWarnBytes = 25 * 1024 * 1024;
}

/// Outcome of [FoodDayExportService.exportDayToCache].
class FoodDayExportResult {
  const FoodDayExportResult._({
    required this.status,
    this.file,
    this.byteLength,
    this.message,
  });

  const FoodDayExportResult.success({
    required File file,
    required int byteLength,
  }) : this._(
          status: FoodDayExportStatus.success,
          file: file,
          byteLength: byteLength,
        );

  const FoodDayExportResult.blocked(String message)
      : this._(status: FoodDayExportStatus.blocked, message: message);

  const FoodDayExportResult.failed(String message)
      : this._(status: FoodDayExportStatus.failed, message: message);

  final FoodDayExportStatus status;
  final File? file;
  final int? byteLength;
  final String? message;

  bool get isSuccess => status == FoodDayExportStatus.success;
}

enum FoodDayExportStatus { success, blocked, failed }
