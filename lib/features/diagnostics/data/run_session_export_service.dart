import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/diagnostics/data/run_session_export_envelope.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';

/// Assembles / writes / prunes a single Run/Walk session dump for AI share.
///
/// On-device sensitive path: may include Totals leftover **bodies**. Full app
/// export ([AppDataExportService]) must never embed those bodies — IDs/len only.
class RunSessionExportService {
  RunSessionExportService({
    required SharedPreferences prefs,
    required RunSessionStore runSessionStore,
    required bool Function() isSyncInFlight,
    required bool Function() isForgetInFlight,
    required bool Function() isAppExportInFlight,
    required bool Function() isFoodExportInFlight,
    Directory? Function()? exportCacheRootOverride,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        _store = runSessionStore,
        _isSyncInFlight = isSyncInFlight,
        _isForgetInFlight = isForgetInFlight,
        _isAppExportInFlight = isAppExportInFlight,
        _isFoodExportInFlight = isFoodExportInFlight,
        _exportCacheRootOverride = exportCacheRootOverride,
        _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final RunSessionStore _store;
  final bool Function() _isSyncInFlight;
  final bool Function() _isForgetInFlight;
  final bool Function() _isAppExportInFlight;
  final bool Function() _isFoodExportInFlight;
  final Directory? Function()? _exportCacheRootOverride;
  final DateTime Function() _clock;

  bool _exportInFlight = false;

  bool get exportInFlight => _exportInFlight;

  bool get isBusy =>
      _isSyncInFlight() ||
      _isForgetInFlight() ||
      _isAppExportInFlight() ||
      _isFoodExportInFlight() ||
      _exportInFlight;

  /// Human-readable session identity for the confirm dialog (matches dump key).
  static String confirmIdentityLines(WorkoutSummary workout) {
    final typeLabel = _typeLabel(workout.type);
    final start = _formatStart(workout.startTime);
    final duration = _formatDuration(workout.durationSec);
    final distance = workout.distanceM != null
        ? '${workout.distanceM} m'
        : 'distance unknown';
    return 'Workout #${workout.number}\n'
        'Start: $start\n'
        'Type: ${workout.type} ($typeLabel)\n'
        'Distance / duration: $distance / $duration';
  }

  /// Walk (1), Outdoor Run (2), Indoor run (5) — matches Run/Walk tab filter.
  static bool isExportableSession(WorkoutSummary workout) =>
      workout.type == 1 || workout.type == 2 || workout.type == 5;

  /// Assemble, redact, write under run-session export cache, prune prior files.
  Future<RunSessionExportResult> exportSessionToCache(
    WorkoutSummary workout,
  ) async {
    if (!isExportableSession(workout)) {
      return const RunSessionExportResult.failed(
        'Session export is Run/Walk only',
      );
    }
    if (isBusy) {
      return const RunSessionExportResult.blocked(
        'Export blocked — sync, Forget, or another export in progress',
      );
    }
    _exportInFlight = true;
    try {
      final envelope = await assembleSessionDump(workout);
      final redacted = _redactEnvelope(envelope);
      final selfCheck = _redactionSelfCheck(redacted);
      if (selfCheck != null) {
        return RunSessionExportResult.failed(
          'Export redaction failed — $selfCheck',
        );
      }
      // Mid-assemble recheck (ignore self flag).
      if (_externalBusy()) {
        return const RunSessionExportResult.blocked(
          'Export blocked — sync, Forget, or another export started during assemble',
        );
      }
      final file = await _writeEnvelope(redacted, workout.number);
      await _prunePriorExports(keep: file);
      if (!_isUnderExportCache(file)) {
        try {
          await file.delete();
        } catch (_) {}
        return const RunSessionExportResult.failed(
          'Export path escaped cache — refused',
        );
      }
      return RunSessionExportResult.success(
        file: file,
        byteLength: await file.length(),
      );
    } on FileSystemException catch (e) {
      return RunSessionExportResult.failed('Export write failed — ${e.message}');
    } catch (e) {
      return RunSessionExportResult.failed('Export failed — $e');
    } finally {
      _exportInFlight = false;
    }
  }

  /// Removes run-session export cache (Forget wipe).
  Future<void> pruneExportCache() async {
    try {
      final dir = await _exportCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort prune.
    }
  }

  /// Builds the session dump (pre-redaction). Prefer leftovers bodies + stream
  /// honesty; GPS / secrets never included.
  Future<Map<String, dynamic>> assembleSessionDump(
    WorkoutSummary workout,
  ) async {
    final leftovers = await _store.loadTotalsLeftovers(workout.number);
    final dataPages = await _store.loadDataPages(workout.number);
    final paceBlocks = await _store.loadPaceBlocks(workout.number);

    final leftoverRefs = leftovers
        .map((b) => {'id': b.id, 'len': b.len})
        .toList(growable: false);
    final leftoverBodies = leftovers.map((b) => b.toJson()).toList();

    final dataPageInventory = dataPages
        .map(
          (p) => {
            'index': p.index,
            if (p.distanceM != null) 'distanceM': p.distanceM,
            if (p.paceSec != null) 'paceSec': p.paceSec,
            'items': [
              for (final b in p.bodies) {'id': b.id, 'len': b.len},
            ],
            'bodyCount': p.bodies.length,
            'bodiesPresent': p.bodies.isNotEmpty,
            // On-device AI path — same sensitivity class as Totals leftovers.
            'bodies': [for (final b in p.bodies) b.toJson()],
          },
        )
        .toList(growable: false);

    final paceInventory = paceBlocks
        .map(
          (p) => {
            'index': p.index,
            if (p.distanceM != null) 'distanceM': p.distanceM,
            if (p.paceSec != null) 'paceSec': p.paceSec,
            'items': [
              for (final b in p.bodies) {'id': b.id, 'len': b.len},
            ],
            'bodyCount': p.bodies.length,
            'bodiesPresent': p.bodies.isNotEmpty,
            'bodies': [for (final b in p.bodies) b.toJson()],
          },
        )
        .toList(growable: false);

    final dataCount = workout.dataCount;
    final paceCount = workout.paceCount;
    final dataHonesty = workout.dataPagesStatus ??
        _inferStreamHonesty(
          countHint: dataCount,
          arrived: dataPages.length,
          stored: workout.dataPagesStored,
        );
    final paceHonesty = workout.paceBlocksStatus ??
        _inferStreamHonesty(
          countHint: paceCount,
          arrived: paceBlocks.length,
          stored: workout.paceBlocksStored,
        );
    final leftoversHonesty = workout.leftoversStatus ??
        (leftovers.isEmpty
            ? WorkoutStreamHonesty.unobserved
            : WorkoutStreamHonesty.present);

    return {
      'schemaVersion': RunSessionExportEnvelope.schemaVersion,
      'kind': RunSessionExportEnvelope.kind,
      'exportedAt': _clock().toUtc().toIso8601String(),
      'sensitivityNotes': RunSessionExportEnvelope.sensitivityNotes,
      'consistencyClass': RunSessionExportEnvelope.consistencyClass,
      'knownOmissions':
          (RunSessionExportEnvelope.alwaysOmitted.toList()..sort()),
      'sessionKey': {
        'number': workout.number,
        'startTime': workout.startTime,
        'type': workout.type,
        if (workout.observedType != null) 'observedType': workout.observedType,
        'typeLabel': _typeLabel(workout.type),
        if (workout.distanceM != null) 'distanceM': workout.distanceM,
        'durationSec': workout.durationSec,
      },
      'confirmIdentity': confirmIdentityLines(workout),
      'workout': workout.toJson(),
      'countHints': {
        if (dataCount != null) 'dataCount': dataCount,
        if (paceCount != null) 'paceCount': paceCount,
        if (workout.sampleCount != null) 'sampleCount': workout.sampleCount,
      },
      'honesty': {
        if (workout.enrichmentStatus != null)
          'enrichmentStatus': workout.enrichmentStatus,
        'leftoversStatus': leftoversHonesty,
        'dataPagesStatus': dataHonesty,
        'paceBlocksStatus': paceHonesty,
      },
      'leftovers': {
        'status': leftoversHonesty,
        'refs': leftoverRefs,
        // On-device AI path only — never commit real dumps with bodies.
        'bodies': leftoverBodies,
        'sideFilePresent': leftovers.isNotEmpty,
      },
      'dataPages': {
        'status': dataHonesty,
        if (workout.dataPagesStored != null)
          'storedCount': workout.dataPagesStored,
        'pages': dataPageInventory,
        'sideFilePresent': dataPages.isNotEmpty,
        if (dataCount != null && dataCount <= 0) 'noPagesHint': true,
        if (dataHonesty == WorkoutStreamHonesty.partial) 'partial': true,
      },
      'paceBlocks': {
        'status': paceHonesty,
        if (workout.paceBlocksStored != null)
          'storedCount': workout.paceBlocksStored,
        'pages': paceInventory,
        'sideFilePresent': paceBlocks.isNotEmpty,
        if (paceCount != null && paceCount <= 0) 'noPagesHint': true,
        if (paceHonesty == WorkoutStreamHonesty.partial) 'partial': true,
      },
    };
  }

  bool _externalBusy() =>
      _isSyncInFlight() ||
      _isForgetInFlight() ||
      _isAppExportInFlight() ||
      _isFoodExportInFlight();

  String _inferStreamHonesty({
    required int? countHint,
    required int arrived,
    required int? stored,
  }) {
    if (countHint != null && countHint <= 0 && arrived == 0) {
      return WorkoutStreamHonesty.unobserved;
    }
    if (arrived > 0 || (stored != null && stored > 0)) {
      if (countHint != null && countHint > arrived) {
        return WorkoutStreamHonesty.partial;
      }
      return WorkoutStreamHonesty.present;
    }
    if (countHint != null && countHint > 0) {
      return WorkoutStreamHonesty.partial;
    }
    return WorkoutStreamHonesty.unobserved;
  }

  Map<String, dynamic> _redactEnvelope(Map<String, dynamic> input) {
    final knownSecretValues = <String>{
      if (_prefs.getString(GateAPrefs.geminiApiKey) case final k?
          when k.isNotEmpty)
        k,
      if (_prefs.getString(GateAPrefs.rememberedMac) case final m?
          when m.isNotEmpty)
        m,
    };
    return _redactNode(input, knownSecretValues) as Map<String, dynamic>;
  }

  dynamic _redactNode(dynamic node, Set<String> secretValues) {
    if (node is Map) {
      final out = <String, dynamic>{};
      for (final e in node.entries) {
        final key = e.key.toString();
        if (_forbiddenKeys.contains(key) ||
            _forbiddenKeys.contains(key.toLowerCase())) {
          continue;
        }
        // GPS / location series omitted this cut.
        if (_gpsKeys.contains(key) || _gpsKeys.contains(key.toLowerCase())) {
          continue;
        }
        final value = _redactNode(e.value, secretValues);
        if (value == null && e.value is String) continue;
        out[key] = value;
      }
      return out;
    }
    if (node is List) {
      final out = <dynamic>[];
      for (final item in node) {
        final value = _redactNode(item, secretValues);
        if (item is String && value == null) continue;
        out.add(value);
      }
      return out;
    }
    if (node is String) {
      if (secretValues.contains(node)) return null;
      if (_macColon.hasMatch(node) ||
          _macDash.hasMatch(node) ||
          _macPlain.hasMatch(node) ||
          _userId.hasMatch(node)) {
        return null;
      }
      return node;
    }
    return node;
  }

  String? _redactionSelfCheck(Map<String, dynamic> envelope) {
    final encoded = jsonEncode(envelope);
    if (_macColon.hasMatch(encoded) ||
        _macDash.hasMatch(encoded) ||
        _macPlain.hasMatch(encoded)) {
      return 'MAC shape detected';
    }
    if (_userId.hasMatch(encoded)) {
      return 'userId shape detected';
    }
    final gemini = _prefs.getString(GateAPrefs.geminiApiKey);
    if (gemini != null && gemini.isNotEmpty && encoded.contains(gemini)) {
      return 'gemini_api_key value detected';
    }
    final mac = _prefs.getString(GateAPrefs.rememberedMac);
    if (mac != null && mac.isNotEmpty && encoded.contains(mac)) {
      return 'remembered_mac value detected';
    }
    if (_containsForbiddenKey(envelope)) {
      return 'forbidden key detected';
    }
    return null;
  }

  bool _containsForbiddenKey(dynamic node) {
    if (node is Map) {
      for (final e in node.entries) {
        final key = e.key.toString();
        if (_forbiddenKeys.contains(key) ||
            _forbiddenKeys.contains(key.toLowerCase()) ||
            _gpsKeys.contains(key) ||
            _gpsKeys.contains(key.toLowerCase())) {
          return true;
        }
        if (_containsForbiddenKey(e.value)) return true;
      }
    } else if (node is List) {
      for (final item in node) {
        if (_containsForbiddenKey(item)) return true;
      }
    }
    return false;
  }

  Future<File> _writeEnvelope(
    Map<String, dynamic> envelope,
    int workoutNumber,
  ) async {
    final dir = await _exportCacheDir();
    final stamp = _clock().toUtc();
    final y = stamp.year.toString().padLeft(4, '0');
    final m = stamp.month.toString().padLeft(2, '0');
    final d = stamp.day.toString().padLeft(2, '0');
    final hh = stamp.hour.toString().padLeft(2, '0');
    final mm = stamp.minute.toString().padLeft(2, '0');
    final ss = stamp.second.toString().padLeft(2, '0');
    final name =
        'run_session_${workoutNumber}_v${RunSessionExportEnvelope.schemaVersion}_$y$m${d}_$hh$mm$ss.json';
    final file = File('${dir.path}/$name');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(envelope),
    );
    return file;
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

  Future<Directory> _exportCacheDir() async {
    final override = _exportCacheRootOverride?.call();
    final root = override ?? await getTemporaryDirectory();
    final dir = Directory(
      '${root.path}/${RunSessionExportEnvelope.exportCacheDirName}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  bool _isUnderExportCache(File file) {
    final path = file.absolute.path;
    final override = _exportCacheRootOverride?.call();
    if (override != null) {
      final cache =
          '${override.absolute.path}/${RunSessionExportEnvelope.exportCacheDirName}';
      return path == cache || path.startsWith('$cache/');
    }
    const marker = '/${RunSessionExportEnvelope.exportCacheDirName}/';
    return path.contains(marker);
  }

  /// Keep aligned with [kWorkoutTypeLabels] / U4 Outdoor=2, Indoor=5.
  static String _typeLabel(int type) {
    const names = <int, String>{
      1: 'Walk',
      2: 'Run',
      3: 'Cycle',
      4: 'Climb',
      5: 'Indoor run',
      6: 'Pool swim',
      7: 'Indoor cycle',
      8: 'Open water',
      9: 'Elliptical',
      10: 'Rower',
      140: 'Strength',
    };
    return names[type] ?? 'Workout type $type';
  }

  static String _formatStart(int unixSec) {
    if (unixSec <= 0) return 'unknown time';
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  static String _formatDuration(int sec) {
    if (sec <= 0) return '—';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  static final _macColon = RegExp(
    r'\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b',
  );
  static final _macDash = RegExp(
    r'\b([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}\b',
  );
  static final _macPlain = RegExp(r'\b[0-9A-Fa-f]{12}\b');
  static final _userId = RegExp(r'\b\d{17}\b');

  static const _forbiddenKeys = {
    'gemini_api_key',
    'geminiApiKey',
    'remembered_mac',
    'rememberedMac',
    'mac',
    'userId',
    'accountId',
    'account_id',
    'phoneMac',
    'authKey',
    'auth_key',
    'bindToken',
    'bind_token',
    'secret',
    'secrets',
  };

  static const _gpsKeys = {
    'gps',
    'gpsTrack',
    'gps_track',
    'location',
    'locations',
    'latLng',
    'latitude',
    'longitude',
    'coordinates',
  };
}

/// Outcome of [RunSessionExportService.exportSessionToCache].
class RunSessionExportResult {
  const RunSessionExportResult._({
    required this.status,
    this.file,
    this.byteLength,
    this.message,
  });

  const RunSessionExportResult.success({
    required File file,
    required int byteLength,
  }) : this._(
          status: RunSessionExportStatus.success,
          file: file,
          byteLength: byteLength,
        );

  const RunSessionExportResult.blocked(String message)
      : this._(status: RunSessionExportStatus.blocked, message: message);

  const RunSessionExportResult.failed(String message)
      : this._(status: RunSessionExportStatus.failed, message: message);

  final RunSessionExportStatus status;
  final File? file;
  final int? byteLength;
  final String? message;

  bool get isSuccess => status == RunSessionExportStatus.success;
}

enum RunSessionExportStatus { success, blocked, failed }
