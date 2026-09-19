import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/data/workout_leftover_store.dart';
import 'package:fitness_os/features/workout_history/domain/repositories/workout_history_repository.dart';

/// Assembles / writes / prunes the owner-initiated swim-session prove JSON.
///
/// Cache peer to food-day: temp/`swim_session_exports/` (not app-data `exports/`).
/// Share by path only — never SoT leftover/sample paths, never [XFile.fromData].
class SwimSessionExportService {
  SwimSessionExportService({
    required WorkoutHistoryRepository repository,
    required WorkoutLeftoverStore leftoverStore,
    required bool Function() isForgetInFlight,
    required bool Function() isSyncOrMergeInFlight,
    Directory? Function()? sideFileRootOverride,
    Directory? Function()? exportCacheRootOverride,
    DateTime Function()? clock,
  })  : _repository = repository,
        _leftoverStore = leftoverStore,
        _isForgetInFlight = isForgetInFlight,
        _isSyncOrMergeInFlight = isSyncOrMergeInFlight,
        _sideFileRootOverride = sideFileRootOverride,
        _exportCacheRootOverride = exportCacheRootOverride,
        _clock = clock ?? DateTime.now;

  final WorkoutHistoryRepository _repository;
  final WorkoutLeftoverStore _leftoverStore;
  final bool Function() _isForgetInFlight;
  final bool Function() _isSyncOrMergeInFlight;
  final Directory? Function()? _sideFileRootOverride;
  final Directory? Function()? _exportCacheRootOverride;
  final DateTime Function() _clock;

  bool _exportInFlight = false;

  bool get exportInFlight => _exportInFlight;

  /// Forget **or** workout Sync/merge **or** this export — AppData [isBusy] peer.
  bool get isBusy =>
      _isForgetInFlight() ||
      _isSyncOrMergeInFlight() ||
      _exportInFlight;

  /// Export the opened swim session (reload SoT by [workoutNumber]).
  Future<SwimSessionExportResult> exportSessionToCache(
    int workoutNumber,
  ) async {
    if (_externalBusy) {
      return const SwimSessionExportResult.blocked(
        'Export blocked — sync, merge, or Forget in progress',
      );
    }

    _exportInFlight = true;
    try {
      final local = await _repository.loadLocal();
      final match = local.where((w) => w.number == workoutNumber).toList();
      if (match.isEmpty) {
        return const SwimSessionExportResult.failed(
          'Session no longer on this device',
        );
      }
      final workout = match.first;
      if (!_isSwimType(workout.type)) {
        return const SwimSessionExportResult.failed(
          'Not a swim session',
        );
      }

      if (_externalBusy) {
        return const SwimSessionExportResult.blocked(
          'Export blocked — sync, merge, or Forget started during assemble',
        );
      }

      final session = await _assembleSession(workout);
      final envelope = {
        'schemaVersion': schemaVersion,
        'exportedAt': _clock().toUtc().toIso8601String(),
        'kind': 'swim_session',
        'sessions': [session],
      };

      final file = await _writeEnvelope(
        envelope,
        nameHint: 'swim_session_$workoutNumber',
      );
      await _prunePriorExports(keep: file);

      if (!_isUnderExportCache(file)) {
        try {
          await file.delete();
        } catch (_) {}
        return const SwimSessionExportResult.failed(
          'Export path escaped cache — refused',
        );
      }

      return SwimSessionExportResult.success(
        file: file,
        byteLength: await file.length(),
      );
    } on FileSystemException catch (e) {
      return SwimSessionExportResult.failed(
        'Export write failed — ${e.message}',
      );
    } catch (e) {
      return SwimSessionExportResult.failed('Export failed — $e');
    } finally {
      _exportInFlight = false;
    }
  }

  /// Explicit all-sessions extra — pool (6) / open water (8) only.
  Future<SwimSessionExportResult> exportAllSwimSessionsToCache() async {
    if (_externalBusy) {
      return const SwimSessionExportResult.blocked(
        'Export blocked — sync, merge, or Forget in progress',
      );
    }

    _exportInFlight = true;
    try {
      final local = await _repository.loadLocal();
      final swims = local
          .where((w) => _isSwimType(w.type))
          .toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));

      if (swims.isEmpty) {
        return const SwimSessionExportResult.failed(
          'No swim sessions to export',
        );
      }

      if (_externalBusy) {
        return const SwimSessionExportResult.blocked(
          'Export blocked — sync, merge, or Forget started during assemble',
        );
      }

      final sessions = <Map<String, dynamic>>[];
      for (final w in swims) {
        sessions.add(await _assembleSession(w));
      }

      final envelope = {
        'schemaVersion': schemaVersion,
        'exportedAt': _clock().toUtc().toIso8601String(),
        'kind': 'swim_sessions',
        'sessionCount': sessions.length,
        'sessions': sessions,
      };

      final file = await _writeEnvelope(
        envelope,
        nameHint: 'swim_sessions',
      );
      await _prunePriorExports(keep: file);

      if (!_isUnderExportCache(file)) {
        try {
          await file.delete();
        } catch (_) {}
        return const SwimSessionExportResult.failed(
          'Export path escaped cache — refused',
        );
      }

      return SwimSessionExportResult.success(
        file: file,
        byteLength: await file.length(),
      );
    } on FileSystemException catch (e) {
      return SwimSessionExportResult.failed(
        'Export write failed — ${e.message}',
      );
    } catch (e) {
      return SwimSessionExportResult.failed('Export failed — $e');
    } finally {
      _exportInFlight = false;
    }
  }

  /// Removes swim export cache (Forget wipe — composed by U6).
  Future<void> pruneSwimExportCache() async {
    try {
      final dir = await _exportCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort prune.
    }
  }

  bool get _externalBusy =>
      _isForgetInFlight() || _isSyncOrMergeInFlight();

  /// Allowlisted session metadata + leftover/sample bodies for the prove dump.
  ///
  /// Identity omit by construction (no MAC / userId / secrets / Gemini).
  /// No zone-minutes object labeled as the watch's; no Fathom recovery %.
  Future<Map<String, dynamic>> _assembleSession(WorkoutSummary w) async {
    final out = <String, dynamic>{
      'number': w.number,
      'startTime': w.startTime,
      'endTime': w.endTime,
      'durationSec': w.durationSec,
      'type': w.type,
    };

    void putIfPresent(String key, Object? value) {
      if (value != null) out[key] = value;
    }

    putIfPresent('calories', w.calories);
    putIfPresent('distanceM', w.distanceM);
    putIfPresent('steps', w.steps);
    putIfPresent('hrMin', w.hrMin);
    putIfPresent('hrMax', w.hrMax);
    putIfPresent('hrPeak', w.hrPeak);
    putIfPresent('load', w.load);
    putIfPresent('aerobicEffect', w.aerobicEffect);
    putIfPresent('anaerobicEffect', w.anaerobicEffect);
    putIfPresent('recoveryTime', w.recoveryTime);
    putIfPresent('trainingPoints', w.trainingPoints);
    putIfPresent('swimType', w.swimType);
    putIfPresent('strokes', w.strokes);
    putIfPresent('strokeRate', w.strokeRate);
    putIfPresent('avgSwolf', w.avgSwolf);
    putIfPresent('poolLength', w.poolLength);
    putIfPresent('laps', w.laps);
    putIfPresent('dataCount', w.dataCount);
    putIfPresent('paceCount', w.paceCount);
    putIfPresent('segmentsCount', w.segmentsCount);
    putIfPresent('sampleCount', w.sampleCount);
    putIfPresent('enrichmentStatus', w.enrichmentStatus);

    final sampleFetch = w.sampleFetch ??
        ((w.dataCount == null || w.dataCount! <= 0) ? 'none' : null);
    putIfPresent('sampleFetch', sampleFetch);

    out['leftover'] = await _assembleLeftover(w);
    out['samples'] = await _assembleSamples(w, sampleFetch: sampleFetch);

    // Honesty: do not invent watch zone minutes or Fathom recovery %.
    // Keys intentionally absent — do not add zoneMinutes / recoveryPercent.

    return out;
  }

  Future<Map<String, dynamic>> _assembleLeftover(WorkoutSummary w) async {
    Uint8List? bytes;
    if (w.leftoverPath != null && w.leftoverPath!.isNotEmpty) {
      bytes = await _leftoverStore.loadAtRelativePath(w.leftoverPath!);
    }
    bytes ??= await _leftoverStore.load(
      workoutNumber: w.number,
      startTime: w.startTime,
    );

    if (bytes != null && bytes.isNotEmpty) {
      return {
        'present': true,
        'len': bytes.length,
        'bytesBase64': base64Encode(bytes),
      };
    }

    final present = w.leftoverPresent == true ||
        (w.leftoverLen != null && w.leftoverLen! > 0);
    return {
      'present': false,
      if (present) 'indexPresent': true,
      if (w.leftoverLen != null) 'indexLen': w.leftoverLen,
      'status': present ? 'unobserved' : 'absent',
    };
  }

  Future<Map<String, dynamic>> _assembleSamples(
    WorkoutSummary w, {
    required String? sampleFetch,
  }) async {
    final fetch = sampleFetch ?? 'none';
    if (fetch == 'none') {
      return {
        'present': false,
        'sampleFetch': 'none',
      };
    }

    final path = w.samplePath;
    if (path == null || path.isEmpty) {
      return {
        'present': false,
        'sampleFetch': fetch,
        'status': 'unobserved',
      };
    }

    final bytes = await _readSampleBytes(path);
    if (bytes != null && bytes.isNotEmpty) {
      return {
        'present': true,
        'sampleFetch': fetch,
        'len': bytes.length,
        // Opaque page bodies = equivalent points until bitmap promote (AE5).
        'pointsBytesBase64': base64Encode(bytes),
      };
    }

    return {
      'present': false,
      'sampleFetch': fetch,
      'status': 'unobserved',
    };
  }

  Future<Uint8List?> _readSampleBytes(String relativePath) async {
    final sanitized = _sanitizeSampleRelative(relativePath);
    if (sanitized == null) return null;
    final root = await _sideFileRoot();
    final file = File('${root.path}/$sanitized');
    try {
      if (!await file.exists()) return null;
      if (!await _isUnderSampleRoot(root, file)) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Canonical path boundary — reject symlink escapes outside hr_samples.
  static Future<bool> _isUnderSampleRoot(Directory root, File file) async {
    try {
      final samples =
          Directory('${root.path}/${GateAPrefs.workoutHrSamplesDir}');
      if (!await samples.exists()) return false;
      final rootCanon = await samples.resolveSymbolicLinks();
      final fileCanon = await file.resolveSymbolicLinks();
      if (fileCanon == rootCanon) return false;
      final sep = Platform.pathSeparator;
      final prefix = rootCanon.endsWith(sep) ? rootCanon : '$rootCanon$sep';
      return fileCanon.startsWith(prefix);
    } catch (_) {
      return false;
    }
  }

  static String? _sanitizeSampleRelative(String path) {
    final trimmed = path.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('/') || trimmed.contains('..')) return null;
    if (trimmed.contains(':\\') || trimmed.startsWith('\\\\')) return null;
    if (!trimmed.startsWith('${GateAPrefs.workoutHrSamplesDir}/')) {
      return null;
    }
    return trimmed;
  }

  Future<File> _writeEnvelope(
    Map<String, dynamic> envelope, {
    required String nameHint,
  }) async {
    final dir = await _exportCacheDir();
    final stamp = _clock().toUtc();
    final y = stamp.year.toString().padLeft(4, '0');
    final m = stamp.month.toString().padLeft(2, '0');
    final d = stamp.day.toString().padLeft(2, '0');
    final hh = stamp.hour.toString().padLeft(2, '0');
    final mm = stamp.minute.toString().padLeft(2, '0');
    final ss = stamp.second.toString().padLeft(2, '0');
    final name = '${nameHint}_$y$m${d}_$hh$mm$ss.json';
    final file = File('${dir.path}/$name');
    final json = const JsonEncoder.withIndent('  ').convert(envelope);
    await file.writeAsString(json, flush: true);
    return file;
  }

  Future<Directory> _sideFileRoot() async {
    final override = _sideFileRootOverride?.call();
    if (override != null) return override;
    return getApplicationSupportDirectory();
  }

  Future<Directory> _exportCacheDir() async {
    final override = _exportCacheRootOverride?.call();
    final root = override ?? await getTemporaryDirectory();
    final dir = Directory('${root.path}/$exportCacheDirName');
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
      if (!entity.path.endsWith('.json')) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  bool _isUnderExportCache(File file) {
    final path = file.absolute.path;
    final override = _exportCacheRootOverride?.call();
    final rootPath = override?.absolute.path;
    // Prefer exact cache-dir prefix when root is known (override / same call).
    // Fallback substring only when temp root cannot be resolved synchronously.
    if (rootPath != null) {
      final cache = '$rootPath/$exportCacheDirName';
      return path == cache ||
          path.startsWith('$cache/') ||
          path.startsWith('$cache\\');
    }
    final marker = '/$exportCacheDirName/';
    final winMarker = '\\$exportCacheDirName\\';
    return path.contains(marker) || path.contains(winMarker);
  }

  static bool _isSwimType(int type) => type == 6 || type == 8;

  static const schemaVersion = 1;
  static const exportCacheDirName = 'swim_session_exports';
  static const softWarnBytes = 25 * 1024 * 1024;
}

/// Outcome of [SwimSessionExportService] export methods.
class SwimSessionExportResult {
  const SwimSessionExportResult._({
    required this.status,
    this.file,
    this.byteLength,
    this.message,
  });

  const SwimSessionExportResult.success({
    required File file,
    required int byteLength,
  }) : this._(
          status: SwimSessionExportStatus.success,
          file: file,
          byteLength: byteLength,
        );

  const SwimSessionExportResult.blocked(String message)
      : this._(status: SwimSessionExportStatus.blocked, message: message);

  const SwimSessionExportResult.failed(String message)
      : this._(status: SwimSessionExportStatus.failed, message: message);

  final SwimSessionExportStatus status;
  final File? file;
  final int? byteLength;
  final String? message;

  bool get isSuccess => status == SwimSessionExportStatus.success;
}

enum SwimSessionExportStatus { success, blocked, failed }
