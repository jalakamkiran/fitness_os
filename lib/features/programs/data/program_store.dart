import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local Programs persistence: lean prefs index + side-file program JSON +
/// lifetime progress ledger.
///
/// Layout: `{appSupport}/programs/{id}.json` + prefs index + ledger JSON.
/// Integrity: write side file to `.tmp` → rename → commit index.
class ProgramStore {
  ProgramStore({
    required SharedPreferences prefs,
    Directory? Function()? rootOverride,
  })  : _prefs = prefs,
        _rootOverride = rootOverride;

  final SharedPreferences _prefs;
  final Directory? Function()? _rootOverride;

  /// Load index entries; corrupt index recovers to empty.
  Future<List<ProgramIndexEntry>> loadIndex() async {
    final raw = _prefs.getString(GateAPrefs.programsIndexJson);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .cast<Map<String, dynamic>>()
          .map(ProgramIndexEntry.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Program?> loadActive() async {
    final index = await loadIndex();
    final active = index.where((e) => e.status == ProgramStatus.active);
    if (active.isEmpty) return null;
    return loadById(active.first.id);
  }

  Future<Program?> loadById(String id) async {
    final root = await _programsRoot();
    final file = File('${root.path}/${GateAPrefs.programsDir}/$id.json');
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return Program.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// Activate [program], archiving any prior active program.
  Future<void> activate(Program program) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final index = List<ProgramIndexEntry>.from(await loadIndex());

    for (var i = 0; i < index.length; i++) {
      if (index[i].status == ProgramStatus.active && index[i].id != program.id) {
        final prior = await loadById(index[i].id);
        if (prior != null) {
          final archived = prior.copyWith(
            status: ProgramStatus.archived,
            archivedAtMs: now,
          );
          await _writeProgramFile(archived);
        }
        index[i] = ProgramIndexEntry(
          id: index[i].id,
          status: ProgramStatus.archived,
          updatedAtMs: now,
          goalDistanceM: index[i].goalDistanceM,
        );
      }
    }

    final activated = program.copyWith(
      status: ProgramStatus.active,
      activatedAtMs: program.activatedAtMs ?? now,
    );
    await _writeProgramFile(activated);

    final entry = ProgramIndexEntry(
      id: activated.id,
      status: ProgramStatus.active,
      updatedAtMs: now,
      goalDistanceM: activated.intake.goalDistanceM,
    );
    final existing = index.indexWhere((e) => e.id == activated.id);
    if (existing >= 0) {
      index[existing] = entry;
    } else {
      index.add(entry);
    }
    await _saveIndex(index);
  }

  /// Persist updates to an existing program (must already be indexed).
  Future<void> save(Program program) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _writeProgramFile(program);
    final index = List<ProgramIndexEntry>.from(await loadIndex());
    final entry = ProgramIndexEntry(
      id: program.id,
      status: program.status,
      updatedAtMs: now,
      goalDistanceM: program.intake.goalDistanceM,
    );
    final existing = index.indexWhere((e) => e.id == program.id);
    if (existing >= 0) {
      index[existing] = entry;
    } else {
      index.add(entry);
    }

    // Enforce single active.
    if (program.status == ProgramStatus.active) {
      for (var i = 0; i < index.length; i++) {
        if (index[i].id != program.id &&
            index[i].status == ProgramStatus.active) {
          final prior = await loadById(index[i].id);
          if (prior != null) {
            await _writeProgramFile(
              prior.copyWith(
                status: ProgramStatus.archived,
                archivedAtMs: now,
              ),
            );
          }
          index[i] = ProgramIndexEntry(
            id: index[i].id,
            status: ProgramStatus.archived,
            updatedAtMs: now,
            goalDistanceM: index[i].goalDistanceM,
          );
        }
      }
    }
    await _saveIndex(index);
  }

  Future<ProgressLedger> loadLedger() async {
    final raw = _prefs.getString(GateAPrefs.programsLedgerJson);
    if (raw == null || raw.isEmpty) return const ProgressLedger();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const ProgressLedger();
      return ProgressLedger.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const ProgressLedger();
    }
  }

  Future<void> saveLedger(ProgressLedger ledger) async {
    await _prefs.setString(
      GateAPrefs.programsLedgerJson,
      jsonEncode(ledger.toJson()),
    );
  }

  /// Forget wipe — prefs + side files.
  Future<void> clearLocal() async {
    await _prefs.remove(GateAPrefs.programsIndexJson);
    await _prefs.remove(GateAPrefs.programsLedgerJson);
    await _prefs.remove(GateAPrefs.programsHideGameLayer);

    final root = await _programsRoot();
    final dir = Directory('${root.path}/${GateAPrefs.programsDir}');
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort wipe.
    }
  }

  Future<void> _writeProgramFile(Program program) async {
    final root = await _programsRoot();
    final dir = Directory('${root.path}/${GateAPrefs.programsDir}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final finalPath = '${dir.path}/${program.id}.json';
    final tempPath = '$finalPath.tmp';
    final temp = File(tempPath);
    try {
      await temp.writeAsString(jsonEncode(program.toJson()));
      await temp.rename(finalPath);
    } catch (e) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _saveIndex(List<ProgramIndexEntry> index) async {
    await _prefs.setString(
      GateAPrefs.programsIndexJson,
      jsonEncode(index.map((e) => e.toJson()).toList()),
    );
  }

  Future<Directory> _programsRoot() async {
    final override = _rootOverride?.call();
    return override ?? await getApplicationSupportDirectory();
  }
}
