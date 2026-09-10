import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:path_provider/path_provider.dart';

/// Side-file SoT for Totals leftover / recovery-HR opaque bytes.
///
/// Layout: `{appSupport}/workouts/leftovers/{number}_{startTime}.bin`
/// Integrity: write temp in same dir → rename to final (FoodMealStore peer).
/// Prefs never hold bodies — only relative path + length on [WorkoutSummary].
class WorkoutLeftoverStore {
  WorkoutLeftoverStore({Directory? Function()? rootOverride})
      : _rootOverride = rootOverride;

  final Directory? Function()? _rootOverride;

  /// Relative path under app support (GateAPrefs dir + filename).
  static String relativePathFor({
    required int workoutNumber,
    required int startTime,
  }) =>
      '${GateAPrefs.workoutLeftoversDir}/'
      '${workoutNumber}_$startTime.bin';

  /// Persist leftover bytes. Returns relative path on success.
  ///
  /// Integrity: write to `.tmp` → rename → return path. Throws on failure
  /// after best-effort temp cleanup (caller must not claim leftover-keep landed).
  Future<String> save({
    required int workoutNumber,
    required int startTime,
    required List<int> bytes,
  }) async {
    final root = await _root();
    final dir = Directory('${root.path}/${GateAPrefs.workoutLeftoversDir}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final rel = relativePathFor(
      workoutNumber: workoutNumber,
      startTime: startTime,
    );
    final finalPath = '${root.path}/$rel';
    final tempPath = '$finalPath.tmp';
    final tempFile = File(tempPath);

    try {
      await tempFile.writeAsBytes(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        flush: true,
      );
      await tempFile.rename(finalPath);
    } catch (_) {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      rethrow;
    }
    return rel;
  }

  /// Load bytes by workout identity. Missing file → null (unobserved, not zero).
  Future<Uint8List?> load({
    required int workoutNumber,
    required int startTime,
  }) =>
      loadAtRelativePath(
        relativePathFor(workoutNumber: workoutNumber, startTime: startTime),
      );

  /// Load by relative path from the lean prefs index.
  /// Missing / unreadable → null (present flag + missing file = unobserved).
  Future<Uint8List?> loadAtRelativePath(String relativePath) async {
    final sanitized = _sanitizeRelative(relativePath);
    if (sanitized == null) return null;
    final root = await _root();
    final file = File('${root.path}/$sanitized');
    try {
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Forget wipe: delete leftover side-file tree (best-effort).
  Future<void> clearLocal() async {
    final root = await _root();
    final dir = Directory('${root.path}/${GateAPrefs.workoutLeftoversDir}');
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort wipe.
    }
  }

  Future<Directory> _root() async {
    final override = _rootOverride?.call();
    return override ?? await getApplicationSupportDirectory();
  }

  /// Reject absolute paths and path escape; require registered leftovers dir.
  static String? _sanitizeRelative(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('/') || trimmed.contains('..')) return null;
    if (trimmed.contains(':\\') || trimmed.startsWith('\\\\')) return null;
    if (!trimmed.startsWith('${GateAPrefs.workoutLeftoversDir}/')) {
      return null;
    }
    return trimmed;
  }
}
