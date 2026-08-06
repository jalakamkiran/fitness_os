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
    Directory? Function()? sideFileRootOverride,
    Directory? Function()? exportCacheRootOverride,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        _isSyncInFlight = isSyncInFlight,
        _isVitalsSyncOrMergeInFlight = isVitalsSyncOrMergeInFlight,
        _isForgetInFlight = isForgetInFlight,
        _isQwenInstalled = isQwenInstalled,
        _sideFileRootOverride = sideFileRootOverride,
        _exportCacheRootOverride = exportCacheRootOverride,
        _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final bool Function() _isSyncInFlight;
  final bool Function() _isVitalsSyncOrMergeInFlight;
  final bool Function() _isForgetInFlight;
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
      _exportInFlight;

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
        if (n is num) workoutNumbers.add(n.toInt());
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
          'parseErrors': [
            ...swimInventory.parseErrors,
            ...hrInventory.parseErrors,
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
}

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
