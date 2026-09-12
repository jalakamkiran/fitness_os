import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/workout_tcx_builder.dart';

/// Owner-initiated TCX export for third-party upload (e.g. Strava website).
///
/// Cache dir is a peer of app-data / food exports — never write SoT paths.
class WorkoutTcxExportService {
  WorkoutTcxExportService({
    required bool Function() isForgetInFlight,
    Directory? Function()? exportCacheRootOverride,
  })  : _isForgetInFlight = isForgetInFlight,
        _exportCacheRootOverride = exportCacheRootOverride;

  static const exportCacheDirName = 'workout_tcx_exports';

  final bool Function() _isForgetInFlight;
  final Directory? Function()? _exportCacheRootOverride;

  bool _exportInFlight = false;

  bool get exportInFlight => _exportInFlight;

  /// Build TCX under export cache; prune prior files for this stem family.
  Future<WorkoutTcxExportResult> exportToCache(WorkoutSummary workout) async {
    if (_isForgetInFlight()) {
      return const WorkoutTcxExportResult.blocked(
        'Export blocked — Forget in progress',
      );
    }
    if (workout.startTime <= 0 || workout.durationSec < 0) {
      return const WorkoutTcxExportResult.failed(
        'Workout missing start time or duration',
      );
    }

    _exportInFlight = true;
    try {
      if (_isForgetInFlight()) {
        return const WorkoutTcxExportResult.blocked(
          'Export blocked — Forget started during assemble',
        );
      }

      final xml = buildWorkoutTcx(workout);
      final stem = workoutTcxFileStem(workout);
      final dir = await _exportCacheDir();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/$stem.tcx');
      await file.writeAsString(xml, flush: true);
      await _prunePriorExports(keep: file);

      if (!_isUnderExportCache(file)) {
        try {
          await file.delete();
        } catch (_) {}
        return const WorkoutTcxExportResult.failed(
          'Export path escaped cache — refused',
        );
      }

      return WorkoutTcxExportResult.success(
        file: file,
        byteLength: await file.length(),
      );
    } on FileSystemException catch (e) {
      return WorkoutTcxExportResult.failed('Export write failed — ${e.message}');
    } catch (e) {
      return WorkoutTcxExportResult.failed('Export failed — $e');
    } finally {
      _exportInFlight = false;
    }
  }

  /// Forget wipe — drop TCX cache.
  Future<void> pruneExportCache() async {
    try {
      final dir = await _exportCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort.
    }
  }

  bool isSharePathAllowed(File file) => _isUnderExportCache(file);

  Future<Directory> _exportCacheDir() async {
    final override = _exportCacheRootOverride?.call();
    if (override != null) return Directory('${override.path}/$exportCacheDirName');
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}/$exportCacheDirName');
  }

  Future<void> _prunePriorExports({required File keep}) async {
    try {
      final dir = await _exportCacheDir();
      if (!await dir.exists()) return;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (entity.path == keep.path) continue;
        if (!entity.path.endsWith('.tcx')) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  bool _isUnderExportCache(File file) {
    final path = file.absolute.path;
    return path.contains('/$exportCacheDirName/') && path.endsWith('.tcx');
  }
}

class WorkoutTcxExportResult {
  const WorkoutTcxExportResult._({
    required this.status,
    this.file,
    this.byteLength,
    this.message,
  });

  const WorkoutTcxExportResult.success({
    required File file,
    required int byteLength,
  }) : this._(status: WorkoutTcxExportStatus.success, file: file, byteLength: byteLength);

  const WorkoutTcxExportResult.failed(String message)
      : this._(status: WorkoutTcxExportStatus.failed, message: message);

  const WorkoutTcxExportResult.blocked(String message)
      : this._(status: WorkoutTcxExportStatus.blocked, message: message);

  final WorkoutTcxExportStatus status;
  final File? file;
  final int? byteLength;
  final String? message;

  bool get isSuccess => status == WorkoutTcxExportStatus.success;
}

enum WorkoutTcxExportStatus { success, failed, blocked }
