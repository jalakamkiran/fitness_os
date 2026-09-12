import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/diagnostics/data/app_data_export_envelope.dart';

/// Assembles / writes / prunes the owner-initiated app-data JSON export.
class AppDataExportService {
  AppDataExportService({
    required SharedPreferences prefs,
    required bool Function() isSyncInFlight,
    required bool Function() isVitalsSyncOrMergeInFlight,
    required bool Function() isForgetInFlight,
    required Future<bool> Function() isQwenInstalled,
    bool Function()? isWorkoutSyncOrMergeInFlight,
    bool Function()? isStrengthExportInFlight,
    Directory? Function()? sideFileRootOverride,
    Directory? Function()? exportCacheRootOverride,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        _isSyncInFlight = isSyncInFlight,
        _isVitalsSyncOrMergeInFlight = isVitalsSyncOrMergeInFlight,
        _isForgetInFlight = isForgetInFlight,
        _isWorkoutSyncOrMergeInFlight = isWorkoutSyncOrMergeInFlight,
        _isStrengthExportInFlight = isStrengthExportInFlight,
        _isQwenInstalled = isQwenInstalled,
        _sideFileRootOverride = sideFileRootOverride,
        _exportCacheRootOverride = exportCacheRootOverride,
        _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final bool Function() _isSyncInFlight;
  final bool Function() _isVitalsSyncOrMergeInFlight;
  final bool Function() _isForgetInFlight;
  final bool Function()? _isWorkoutSyncOrMergeInFlight;
  final bool Function()? _isStrengthExportInFlight;
  final Future<bool> Function() _isQwenInstalled;
  final Directory? Function()? _sideFileRootOverride;
  final Directory? Function()? _exportCacheRootOverride;
  final DateTime Function() _clock;

  bool _exportInFlight = false;

  bool get exportInFlight => _exportInFlight;

  bool get isBusy =>
      _isSyncInFlight() ||
      _isVitalsSyncOrMergeInFlight() ||
      _isForgetInFlight() ||
      (_isWorkoutSyncOrMergeInFlight?.call() ?? false) ||
      (_isStrengthExportInFlight?.call() ?? false) ||
      _exportInFlight;

  bool get _externalBusy =>
      _isSyncInFlight() ||
      _isVitalsSyncOrMergeInFlight() ||
      _isForgetInFlight() ||
      (_isWorkoutSyncOrMergeInFlight?.call() ?? false) ||
      (_isStrengthExportInFlight?.call() ?? false);

  /// Assemble, redact, write under export cache, prune prior files.
  Future<AppDataExportResult> exportToCache() async {
    if (isBusy) {
      return const AppDataExportResult.blocked('Export blocked — sync or Forget in progress');
    }
    _exportInFlight = true;
    try {
      final envelope = await assembleEnvelope();
      final redacted = _redactEnvelope(envelope);
      final selfCheck = _redactionSelfCheck(redacted);
      if (selfCheck != null) {
        return AppDataExportResult.failed(
          'Export redaction failed — $selfCheck',
        );
      }
      // Re-check external busy immediately before write (ignore self flag).
      if (_externalBusy) {
        return const AppDataExportResult.blocked(
          'Export blocked — sync or Forget started during assemble',
        );
      }
      final file = await _writeEnvelope(redacted);
      await _prunePriorExports(keep: file);
      if (!_isUnderExportCache(file)) {
        try {
          await file.delete();
        } catch (_) {}
        return const AppDataExportResult.failed(
          'Export path escaped cache — refused',
        );
      }
      return AppDataExportResult.success(
        file: file,
        byteLength: await file.length(),
      );
    } on FileSystemException catch (e) {
      return AppDataExportResult.failed('Export write failed — ${e.message}');
    } catch (e) {
      return AppDataExportResult.failed('Export failed — $e');
    } finally {
      _exportInFlight = false;
    }
  }

  /// Removes export cache and share_plus residual copies (Forget wipe).
  Future<void> pruneExportCache() async {
    try {
      final dir = await _exportCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort prune.
    }
    try {
      // share_plus copies shared files into cacheDir/share_plus before grant.
      final temp = await getTemporaryDirectory();
      final shareCache = Directory('${temp.path}/share_plus');
      if (await shareCache.exists()) {
        await shareCache.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort prune.
    }
  }

  /// Builds the versioned envelope from prefs + raw side-file listings.
  Future<Map<String, dynamic>> assembleEnvelope() async {
    final root = await _sideFileRoot();
    final workoutSection = _decodeJsonListSection(
      _prefs.getString(GateAPrefs.workoutsJson),
    );
    final sleepSection = _decodeJsonListSection(
      _prefs.getString(GateAPrefs.sleepSessionsJson),
    );
    final hrSummarySection = _decodeJsonListSection(
      _prefs.getString(GateAPrefs.dailyHrJson),
    );

    final workoutNumbers = <int>{};
    var hasDataPages = false;
    var hasPaceBlocks = false;
    for (final item in workoutSection.items) {
      if (item is Map) {
        final n = item['number'];
        if (n is num && _looksLikeSwimMap(item)) {
          workoutNumbers.add(n.toInt());
        }
        if (item['dataPages'] is List && (item['dataPages'] as List).isNotEmpty) {
          hasDataPages = true;
        }
        if (item['paceBlocks'] is List &&
            (item['paceBlocks'] as List).isNotEmpty) {
          hasPaceBlocks = true;
        }
      }
    }

    final swimInventory = await _inventoryCanonicalSwim(root, workoutNumbers);
    final hrInventory = await _inventoryHrSeries(
      root,
      _dayKeysFromSummaries(hrSummarySection.items),
    );
    final runSessionInventory = await _inventoryRunSessionSideFiles(root);

    final hasCoachOutputs =
        _prefs.containsKey('ephemeral_coach_reasoner_outputs') ||
            _prefs.containsKey('coach_reasoner_outputs_json');
    final hasDiagnosisSnapshots =
        _prefs.containsKey('diagnosis_and_recommendation_snapshots') ||
            _prefs.containsKey('diagnosis_snapshots_json');
    final hasDailyActivityCalories =
        _prefs.containsKey('daily_activity_calories_json') ||
            _prefs.containsKey('fitness_totals_day_calories_json');

    final knownOmissions = <String>[
      for (final key in AppDataExportEnvelope.candidateOmissions)
        if (AppDataExportEnvelope.alwaysOmitted.contains(key) ||
            (key == 'swim_sample_data_pages' && !hasDataPages) ||
            (key == 'swim_pace_blocks' && !hasPaceBlocks) ||
            (key == 'ephemeral_coach_reasoner_outputs' && !hasCoachOutputs) ||
            (key == 'diagnosis_and_recommendation_snapshots' &&
                !hasDiagnosisSnapshots) ||
            (key == 'daily_activity_calories_beyond_workout_totals_sum' &&
                !hasDailyActivityCalories))
          key,
    ];

    final optionalExtras = <String, dynamic>{};
    if (hasCoachOutputs) {
      optionalExtras['ephemeralCoachReasonerOutputs'] =
          _optionalJsonPref('ephemeral_coach_reasoner_outputs') ??
              _optionalJsonPref('coach_reasoner_outputs_json');
    }
    if (hasDiagnosisSnapshots) {
      optionalExtras['diagnosisAndRecommendationSnapshots'] =
          _optionalJsonPref('diagnosis_and_recommendation_snapshots') ??
              _optionalJsonPref('diagnosis_snapshots_json');
    }
    if (hasDailyActivityCalories) {
      optionalExtras['dailyActivityCalories'] =
          _optionalJsonPref('daily_activity_calories_json') ??
              _optionalJsonPref('fitness_totals_day_calories_json');
    }

    final qwenInstalled = await _isQwenInstalled();
    final lastAuto = _optionalJsonPref(GateAPrefs.lastAutoTrackingEnableJson);

    return {
      'schemaVersion': AppDataExportEnvelope.schemaVersion,
      'exportedAt': _clock().toUtc().toIso8601String(),
      'sensitivityNotes': AppDataExportEnvelope.sensitivityNotes,
      'consistencyClass': AppDataExportEnvelope.consistencyClass,
      'knownOmissions': knownOmissions,
      'meta': {
        'swimSegmentParserVersion':
            _prefs.getInt(GateAPrefs.swimSegmentParserVersion),
        'lastSyncCursor': _prefs.getInt(GateAPrefs.lastSyncCursor),
        'lastActivitySyncCursor':
            _prefs.getInt(GateAPrefs.lastActivitySyncCursor),
        'activitySyncImplVersion':
            _prefs.getInt(GateAPrefs.activitySyncImplVersion),
        'gateAPassed': _prefs.getBool(GateAPrefs.gateAPassed) ?? false,
        'gateAInterruptFlags': {
          'killOk': _prefs.getBool(GateAPrefs.gateAKillOk) ?? false,
          'rebootOk': _prefs.getBool(GateAPrefs.gateARebootOk) ?? false,
          'btToggleOk': _prefs.getBool(GateAPrefs.gateABtToggleOk) ?? false,
        },
        'lastR11WinningPath': _prefs.getString(GateAPrefs.lastR11Path),
        if (lastAuto != null) 'lastAutoTrackingEnable': lastAuto,
        'homeLastSyncStatus': _prefs.getString(GateAPrefs.homeLastSyncStatus),
        'homeLastSyncAtMs': _prefs.getInt(GateAPrefs.homeLastSyncAtMs),
        'rememberedName': _prefs.getString(GateAPrefs.rememberedName),
        'qwenInstalled': qwenInstalled,
        'sideFileInventory': {
          'missingCanonicalSwim': swimInventory.missing,
          'orphanCanonicalSwim': swimInventory.orphans,
          'hrSeriesMissingDays': hrInventory.missing,
          'hrSeriesOrphanDays': hrInventory.orphans,
          'runSessionSideFiles': runSessionInventory.toJson(),
          'parseErrors': [
            ...swimInventory.parseErrors,
            ...hrInventory.parseErrors,
            ...runSessionInventory.parseErrors,
          ],
        },
      },
      'workouts': {
        'parseStatus': workoutSection.parseStatus,
        'items': workoutSection.items,
      },
      'canonicalSwim': swimInventory.bodies,
      'vitals': {
        'sleepSessions': {
          'parseStatus': sleepSection.parseStatus,
          'items': sleepSection.items,
        },
        'dailyHrSummaries': {
          'parseStatus': hrSummarySection.parseStatus,
          'items': hrSummarySection.items,
        },
        'hrSeries': hrInventory.series,
      },
      if (optionalExtras.isNotEmpty) 'optionalPresent': optionalExtras,
    };
  }

  Future<Directory?> _sideFileRoot() async {
    final override = _sideFileRootOverride?.call();
    if (override != null) return override;
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _exportCacheDir() async {
    final override = _exportCacheRootOverride?.call();
    final root = override ?? await getTemporaryDirectory();
    final dir = Directory(
      '${root.path}/${AppDataExportEnvelope.exportCacheDirName}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Object? _optionalJsonPref(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return {'_parseStatus': AppDataExportEnvelope.parseCorrupt, 'raw': raw};
    }
  }

  _JsonListSection _decodeJsonListSection(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const _JsonListSection(
        parseStatus: AppDataExportEnvelope.parseAbsent,
        items: [],
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const _JsonListSection(
          parseStatus: AppDataExportEnvelope.parseCorrupt,
          items: [],
        );
      }
      return _JsonListSection(
        parseStatus: AppDataExportEnvelope.parseOk,
        items: List<dynamic>.from(decoded),
      );
    } catch (_) {
      return const _JsonListSection(
        parseStatus: AppDataExportEnvelope.parseCorrupt,
        items: [],
      );
    }
  }

  Set<String> _dayKeysFromSummaries(List<dynamic> items) {
    final out = <String>{};
    for (final item in items) {
      if (item is Map && item['dayKey'] is String) {
        out.add(item['dayKey'] as String);
      }
    }
    return out;
  }

  /// Mirrors [CanonicalSwimSession.looksLikeSwim] for raw prefs maps.
  bool _looksLikeSwimMap(Map<dynamic, dynamic> item) {
    final type = item['type'];
    if (type is num) {
      final t = type.toInt();
      if (t == 6 || t == 8) return true;
      if (t == 5 || t == 7) return false;
    }
    return item['poolLength'] != null ||
        item['strokes'] != null ||
        item['avgSwolf'] != null ||
        (item['segments'] is List && (item['segments'] as List).isNotEmpty);
  }

  Future<_SwimInventory> _inventoryCanonicalSwim(
    Directory? root,
    Set<int> workoutNumbers,
  ) async {
    final missing = <int>[];
    final orphans = <int>[];
    final bodies = <Map<String, dynamic>>[];
    final parseErrors = <String>[];
    if (root == null) {
      missing.addAll(workoutNumbers);
      return _SwimInventory(
        missing: missing..sort(),
        orphans: orphans,
        bodies: bodies,
        parseErrors: parseErrors,
      );
    }

    final dir = Directory('${root.path}/${GateAPrefs.canonicalSwimDir}');
    final onDisk = <int, File>{};
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last;
        final match = RegExp(r'^swim_(\d+)\.json$').firstMatch(name);
        if (match == null) continue;
        onDisk[int.parse(match.group(1)!)] = entity;
      }
    }

    for (final n in workoutNumbers) {
      final file = onDisk[n];
      if (file == null) {
        missing.add(n);
        continue;
      }
      try {
        final map =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        bodies.add({
          'file': 'swim_$n.json',
          'parseStatus': AppDataExportEnvelope.parseOk,
          'body': map,
        });
      } catch (e) {
        parseErrors.add('canonical_swim/swim_$n.json: $e');
        bodies.add({
          'file': 'swim_$n.json',
          'parseStatus': AppDataExportEnvelope.parseCorrupt,
        });
      }
    }

    for (final n in onDisk.keys) {
      if (!workoutNumbers.contains(n)) {
        orphans.add(n);
      }
    }
    missing.sort();
    orphans.sort();
    return _SwimInventory(
      missing: missing,
      orphans: orphans,
      bodies: bodies,
      parseErrors: parseErrors,
    );
  }

  Future<_HrInventory> _inventoryHrSeries(
    Directory? root,
    Set<String> expectedDays,
  ) async {
    final missing = <String>[];
    final orphans = <String>[];
    final series = <Map<String, dynamic>>[];
    final parseErrors = <String>[];
    if (root == null) {
      missing.addAll(expectedDays);
      missing.sort();
      return _HrInventory(
        missing: missing,
        orphans: orphans,
        series: series,
        parseErrors: parseErrors,
      );
    }

    final dir = Directory('${root.path}/${GateAPrefs.dailyHrSeriesDir}');
    final onDisk = <String, File>{};
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.json')) continue;
        final dayKey = name.substring(0, name.length - '.json'.length);
        onDisk[dayKey] = entity;
      }
    }

    for (final day in expectedDays) {
      final file = onDisk[day];
      if (file == null) {
        missing.add(day);
        continue;
      }
      try {
        final map =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        series.add({
          'dayKey': day,
          'parseStatus': AppDataExportEnvelope.parseOk,
          'samples': map['samples'],
        });
      } catch (e) {
        parseErrors.add('hr_series/$day.json: $e');
      }
    }

    for (final day in onDisk.keys) {
      if (!expectedDays.contains(day)) {
        orphans.add(day);
        final file = onDisk[day]!;
        try {
          final map =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          series.add({
            'dayKey': day,
            'parseStatus': AppDataExportEnvelope.parseOk,
            'samples': map['samples'],
          });
        } catch (e) {
          parseErrors.add('hr_series/$day.json: $e');
        }
      }
    }

    missing.sort();
    orphans.sort();
    return _HrInventory(
      missing: missing,
      orphans: orphans,
      series: series,
      parseErrors: parseErrors,
    );
  }

  /// IDs/lengths only for run leftover / data-page / pace side-files — never bodies.
  Future<_RunSessionSideInventory> _inventoryRunSessionSideFiles(
    Directory? root,
  ) async {
    if (root == null) {
      return const _RunSessionSideInventory(
        totalsLeftovers: [],
        dataPages: [],
        paceBlocks: [],
        parseErrors: [],
      );
    }
    final leftovers = await _inventoryIdLenDir(
      root,
      GateAPrefs.workoutTotalsLeftoversDir,
      flat: true,
    );
    final dataPages = await _inventoryIdLenDir(
      root,
      GateAPrefs.workoutDataPagesDir,
      flat: false,
    );
    final paceBlocks = await _inventoryIdLenDir(
      root,
      GateAPrefs.workoutPaceBlocksDir,
      flat: false,
    );
    return _RunSessionSideInventory(
      totalsLeftovers: leftovers.entries,
      dataPages: dataPages.entries,
      paceBlocks: paceBlocks.entries,
      parseErrors: [
        ...leftovers.parseErrors,
        ...dataPages.parseErrors,
        ...paceBlocks.parseErrors,
      ],
    );
  }

  Future<_IdLenDirScan> _inventoryIdLenDir(
    Directory root,
    String relDir, {
    required bool flat,
  }) async {
    final entries = <Map<String, dynamic>>[];
    final parseErrors = <String>[];
    final dir = Directory('${root.path}/$relDir');
    if (!await dir.exists()) {
      return _IdLenDirScan(entries: entries, parseErrors: parseErrors);
    }
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final workoutNumber = int.tryParse(name);
      if (workoutNumber == null) continue;
      final metaFile = File('${entity.path}/meta.json');
      if (!await metaFile.exists()) {
        entries.add({
          'workoutNumber': workoutNumber,
          'parseStatus': AppDataExportEnvelope.parseAbsent,
          'items': <Map<String, dynamic>>[],
        });
        continue;
      }
      try {
        final decoded = jsonDecode(await metaFile.readAsString());
        if (decoded is! Map) {
          parseErrors.add('$relDir/$workoutNumber/meta.json: not a map');
          entries.add({
            'workoutNumber': workoutNumber,
            'parseStatus': AppDataExportEnvelope.parseCorrupt,
            'items': <Map<String, dynamic>>[],
          });
          continue;
        }
        final items = <Map<String, dynamic>>[];
        if (flat) {
          final rawItems = decoded['items'];
          if (rawItems is List) {
            for (final item in rawItems.whereType<Map>()) {
              items.add({
                'id': (item['id'] as num?)?.toInt() ?? 0,
                'len': (item['len'] as num?)?.toInt() ?? 0,
              });
            }
          }
        } else {
          final pages = decoded['pages'];
          if (pages is List) {
            for (final page in pages.whereType<Map>()) {
              final pageItems = page['items'];
              final pageRefs = <Map<String, dynamic>>[];
              if (pageItems is List) {
                for (final item in pageItems.whereType<Map>()) {
                  pageRefs.add({
                    'id': (item['id'] as num?)?.toInt() ?? 0,
                    'len': (item['len'] as num?)?.toInt() ?? 0,
                  });
                }
              }
              items.add({
                'index': (page['index'] as num?)?.toInt() ?? 0,
                'items': pageRefs,
              });
            }
          }
        }
        entries.add({
          'workoutNumber': workoutNumber,
          'parseStatus': AppDataExportEnvelope.parseOk,
          if (flat) 'items': items else 'pages': items,
        });
      } catch (e) {
        parseErrors.add('$relDir/$workoutNumber/meta.json: $e');
        entries.add({
          'workoutNumber': workoutNumber,
          'parseStatus': AppDataExportEnvelope.parseCorrupt,
          'items': <Map<String, dynamic>>[],
        });
      }
    }
    entries.sort((a, b) {
      final an = a['workoutNumber'] as int;
      final bn = b['workoutNumber'] as int;
      return an.compareTo(bn);
    });
    return _IdLenDirScan(entries: entries, parseErrors: parseErrors);
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

  /// Returns a failure reason if secrets/identity shapes remain; null if clean.
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
            _forbiddenKeys.contains(key.toLowerCase())) {
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

  Future<File> _writeEnvelope(Map<String, dynamic> envelope) async {
    final dir = await _exportCacheDir();
    final stamp = _clock().toUtc();
    final y = stamp.year.toString().padLeft(4, '0');
    final m = stamp.month.toString().padLeft(2, '0');
    final d = stamp.day.toString().padLeft(2, '0');
    final hh = stamp.hour.toString().padLeft(2, '0');
    final mm = stamp.minute.toString().padLeft(2, '0');
    final ss = stamp.second.toString().padLeft(2, '0');
    final name =
        'fitness_os_export_v${AppDataExportEnvelope.schemaVersion}_$y$m${d}_$hh$mm$ss.json';
    final file = File('${dir.path}/$name');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(envelope));
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

  bool _isUnderExportCache(File file) {
    final path = file.absolute.path;
    final override = _exportCacheRootOverride?.call();
    if (override != null) {
      final cache =
          '${override.absolute.path}/${AppDataExportEnvelope.exportCacheDirName}';
      return path == cache || path.startsWith('$cache/');
    }
    const marker = '/${AppDataExportEnvelope.exportCacheDirName}/';
    return path.contains(marker);
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
    'phoneMac',
    'authKey',
    'secret',
    'secrets',
  };
}

/// Outcome of [AppDataExportService.exportToCache].
class AppDataExportResult {
  const AppDataExportResult._({
    required this.status,
    this.file,
    this.byteLength,
    this.message,
  });

  const AppDataExportResult.success({
    required File file,
    required int byteLength,
  }) : this._(
          status: AppDataExportStatus.success,
          file: file,
          byteLength: byteLength,
        );

  const AppDataExportResult.blocked(String message)
      : this._(status: AppDataExportStatus.blocked, message: message);

  const AppDataExportResult.failed(String message)
      : this._(status: AppDataExportStatus.failed, message: message);

  final AppDataExportStatus status;
  final File? file;
  final int? byteLength;
  final String? message;

  bool get isSuccess => status == AppDataExportStatus.success;
}

enum AppDataExportStatus { success, blocked, failed }

class _JsonListSection {
  const _JsonListSection({
    required this.parseStatus,
    required this.items,
  });

  final String parseStatus;
  final List<dynamic> items;
}

class _SwimInventory {
  const _SwimInventory({
    required this.missing,
    required this.orphans,
    required this.bodies,
    required this.parseErrors,
  });

  final List<int> missing;
  final List<int> orphans;
  final List<Map<String, dynamic>> bodies;
  final List<String> parseErrors;
}

class _HrInventory {
  const _HrInventory({
    required this.missing,
    required this.orphans,
    required this.series,
    required this.parseErrors,
  });

  final List<String> missing;
  final List<String> orphans;
  final List<Map<String, dynamic>> series;
  final List<String> parseErrors;
}

class _RunSessionSideInventory {
  const _RunSessionSideInventory({
    required this.totalsLeftovers,
    required this.dataPages,
    required this.paceBlocks,
    required this.parseErrors,
  });

  final List<Map<String, dynamic>> totalsLeftovers;
  final List<Map<String, dynamic>> dataPages;
  final List<Map<String, dynamic>> paceBlocks;
  final List<String> parseErrors;

  Map<String, dynamic> toJson() => {
        'totalsLeftovers': totalsLeftovers,
        'dataPages': dataPages,
        'paceBlocks': paceBlocks,
      };
}

class _IdLenDirScan {
  const _IdLenDirScan({
    required this.entries,
    required this.parseErrors,
  });

  final List<Map<String, dynamic>> entries;
  final List<String> parseErrors;
}
