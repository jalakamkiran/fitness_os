import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:path_provider/path_provider.dart';

/// Local side-file store for canonical swim sessions (one JSON per workout #).
class CanonicalSwimStore {
  CanonicalSwimStore({Directory? Function()? rootOverride})
      : _rootOverride = rootOverride;

  final Directory? Function()? _rootOverride;

  Future<Directory> _dir() async {
    final override = _rootOverride?.call();
    final root = override ?? await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/${GateAPrefs.canonicalSwimDir}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _fileFor(int workoutNumber) async {
    final dir = await _dir();
    return File('${dir.path}/swim_$workoutNumber.json');
  }

  Future<void> save(CanonicalSwimSession session) async {
    final file = await _fileFor(session.workoutNumber);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.toJson()),
    );
  }

  Future<CanonicalSwimSession?> load(int workoutNumber) async {
    final file = await _fileFor(workoutNumber);
    if (!await file.exists()) return null;
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return CanonicalSwimSession.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAll(Iterable<CanonicalSwimSession> sessions) async {
    for (final s in sessions) {
      await save(s);
    }
  }

  /// All canonical swim side-files, newest first by startTime.
  Future<List<CanonicalSwimSession>> loadAll() async {
    final dir = await _dir();
    if (!await dir.exists()) return const [];
    final out = <CanonicalSwimSession>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final map =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        out.add(CanonicalSwimSession.fromJson(map));
      } catch (_) {
        // skip corrupt
      }
    }
    out.sort((a, b) => b.startTime.compareTo(a.startTime));
    return out;
  }
}
