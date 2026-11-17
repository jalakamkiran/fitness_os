import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/features/lift/domain/planned_session.dart';
import 'package:fitness_os/features/lift/domain/strength_set.dart';
import 'package:path_provider/path_provider.dart';

class LiftStore {
  LiftStore({Directory? Function()? rootOverride})
      : _rootOverride = rootOverride;

  final Directory? Function()? _rootOverride;

  Future<Directory> _liftRoot() async {
    if (_rootOverride != null) return _rootOverride!();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/lift');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String name) async {
    final root = await _liftRoot();
    return File('${root.path}/$name');
  }

  Future<List<PlannedSession>> loadPlannedSessions() async {
    final file = await _file('planned_sessions.json');
    if (!await file.exists()) return const [];
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      return list
          .map((e) => PlannedSession.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePlannedSessions(List<PlannedSession> sessions) async {
    await _atomicWrite(
      await _file('planned_sessions.json'),
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }

  Future<List<StrengthSet>> loadStrengthSets() async {
    final file = await _file('strength_sets.json');
    if (!await file.exists()) return const [];
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      return list
          .map((e) => StrengthSet.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsertStrengthSet(StrengthSet set) async {
    final all = await loadStrengthSets();
    final idx = all.indexWhere((s) => s.id == set.id);
    if (idx >= 0) {
      all[idx] = set;
    } else {
      all.add(set);
    }
    await _atomicWrite(
      await _file('strength_sets.json'),
      jsonEncode(all.map((s) => s.toJson()).toList()),
    );
    await enqueueUpload(set.id);
  }

  Future<List<String>> loadPendingUploadIds() async {
    final file = await _file('pending_upload.json');
    if (!await file.exists()) return const [];
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      return list.cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> enqueueUpload(String id) async {
    final ids = await loadPendingUploadIds();
    if (!ids.contains(id)) {
      ids.add(id);
      await _atomicWrite(
        await _file('pending_upload.json'),
        jsonEncode(ids),
      );
    }
  }

  Future<void> removePendingUploads(Iterable<String> synced) async {
    final ids = await loadPendingUploadIds();
    ids.removeWhere(synced.contains);
    await _atomicWrite(
      await _file('pending_upload.json'),
      jsonEncode(ids),
    );
  }

  Future<void> _atomicWrite(File file, String body) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }
}