import 'dart:convert';
import 'dart:io';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:path_provider/path_provider.dart';

/// On-device side-file store for peeled Totals leftovers + sample/pace bodies.
///
/// Layout under application support (sport-agnostic):
/// - [GateAPrefs.workoutTotalsLeftoversDir]/{workoutNumber}/meta.json + `*.bin`
/// - [GateAPrefs.workoutDataPagesDir]/{workoutNumber}/meta.json + `*.bin`
/// - [GateAPrefs.workoutPaceBlocksDir]/{workoutNumber}/meta.json + `*.bin`
///
/// Prefs stay lean (ids/counts/lengths + honesty stamps only). Bodies never
/// leave these side-files into SharedPreferences / logs / Sentry.
class RunSessionStore {
  RunSessionStore({Directory? Function()? rootOverride})
      : _rootOverride = rootOverride;

  final Directory? Function()? _rootOverride;

  /// Persist peeled bodies as binary files. No-op when [payload] has nothing
  /// to write (e.g. Count=0 → unobserved).
  Future<void> save(PeeledWorkoutPayload payload) async {
    if (payload.totalsLeftovers.isNotEmpty) {
      await _writeFlatBodies(
        GateAPrefs.workoutTotalsLeftoversDir,
        payload.workoutNumber,
        payload.totalsLeftovers,
      );
    }
    if (payload.dataPages.isNotEmpty) {
      await _writePagedBodies(
        GateAPrefs.workoutDataPagesDir,
        payload.workoutNumber,
        payload.dataPages,
      );
    }
    if (payload.paceBlocks.isNotEmpty) {
      await _writePagedBodies(
        GateAPrefs.workoutPaceBlocksDir,
        payload.workoutNumber,
        payload.paceBlocks,
      );
    }
  }

  Future<List<LeftoverTlvBody>> loadTotalsLeftovers(int workoutNumber) async {
    return _readFlatBodies(
      GateAPrefs.workoutTotalsLeftoversDir,
      workoutNumber,
    );
  }

  Future<List<PeeledPageBodies>> loadDataPages(int workoutNumber) async {
    return _readPagedBodies(
      GateAPrefs.workoutDataPagesDir,
      workoutNumber,
    );
  }

  Future<List<PeeledPageBodies>> loadPaceBlocks(int workoutNumber) async {
    return _readPagedBodies(
      GateAPrefs.workoutPaceBlocksDir,
      workoutNumber,
    );
  }

  /// Wipe all leftover / sample / pace side-file dirs (Forget / U5 composition).
  Future<void> clearLocal() async {
    final root = await _root();
    for (final rel in [
      GateAPrefs.workoutTotalsLeftoversDir,
      GateAPrefs.workoutDataPagesDir,
      GateAPrefs.workoutPaceBlocksDir,
    ]) {
      final dir = Directory('${root.path}/$rel');
      try {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {
        // Best-effort wipe.
      }
    }
  }

  Future<void> _writeFlatBodies(
    String relDir,
    int workoutNumber,
    List<LeftoverTlvBody> bodies,
  ) async {
    final dir = await _workoutDir(relDir, workoutNumber);
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < bodies.length; i++) {
      final body = bodies[i];
      final name = '$i.bin';
      await File('${dir.path}/$name').writeAsBytes(
        base64Decode(body.bodyBase64),
        flush: true,
      );
      items.add({'id': body.id, 'len': body.len, 'file': name});
    }
    await File('${dir.path}/meta.json').writeAsString(
      jsonEncode({'items': items}),
      flush: true,
    );
  }

  Future<void> _writePagedBodies(
    String relDir,
    int workoutNumber,
    List<PeeledPageBodies> pages,
  ) async {
    final dir = await _workoutDir(relDir, workoutNumber);
    final pageMeta = <Map<String, dynamic>>[];
    for (final page in pages) {
      final items = <Map<String, dynamic>>[];
      for (var i = 0; i < page.bodies.length; i++) {
        final body = page.bodies[i];
        final name = 'p${page.index}_$i.bin';
        await File('${dir.path}/$name').writeAsBytes(
          base64Decode(body.bodyBase64),
          flush: true,
        );
        items.add({'id': body.id, 'len': body.len, 'file': name});
      }
      pageMeta.add({'index': page.index, 'items': items});
    }
    await File('${dir.path}/meta.json').writeAsString(
      jsonEncode({'pages': pageMeta}),
      flush: true,
    );
  }

  Future<List<LeftoverTlvBody>> _readFlatBodies(
    String relDir,
    int workoutNumber,
  ) async {
    final dir = await _workoutDir(relDir, workoutNumber, create: false);
    if (!await dir.exists()) return const [];
    final metaFile = File('${dir.path}/meta.json');
    if (!await metaFile.exists()) return const [];
    try {
      final decoded = jsonDecode(await metaFile.readAsString());
      if (decoded is! Map) return const [];
      final items = decoded['items'];
      if (items is! List) return const [];
      final out = <LeftoverTlvBody>[];
      for (final item in items.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        final name = map['file'] as String?;
        if (name == null || name.isEmpty) continue;
        final bytes = await File('${dir.path}/$name').readAsBytes();
        out.add(
          LeftoverTlvBody(
            id: (map['id'] as num?)?.toInt() ?? 0,
            len: (map['len'] as num?)?.toInt() ?? bytes.length,
            bodyBase64: base64Encode(bytes),
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<PeeledPageBodies>> _readPagedBodies(
    String relDir,
    int workoutNumber,
  ) async {
    final dir = await _workoutDir(relDir, workoutNumber, create: false);
    if (!await dir.exists()) return const [];
    final metaFile = File('${dir.path}/meta.json');
    if (!await metaFile.exists()) return const [];
    try {
      final decoded = jsonDecode(await metaFile.readAsString());
      if (decoded is! Map) return const [];
      final pages = decoded['pages'];
      if (pages is! List) return const [];
      final out = <PeeledPageBodies>[];
      for (final page in pages.whereType<Map>()) {
        final pageMap = Map<String, dynamic>.from(page);
        final index = (pageMap['index'] as num?)?.toInt() ?? 0;
        final items = pageMap['items'];
        if (items is! List) continue;
        final bodies = <LeftoverTlvBody>[];
        for (final item in items.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final name = map['file'] as String?;
          if (name == null || name.isEmpty) continue;
          final bytes = await File('${dir.path}/$name').readAsBytes();
          bodies.add(
            LeftoverTlvBody(
              id: (map['id'] as num?)?.toInt() ?? 0,
              len: (map['len'] as num?)?.toInt() ?? bytes.length,
              bodyBase64: base64Encode(bytes),
            ),
          );
        }
        if (bodies.isNotEmpty) {
          out.add(PeeledPageBodies(index: index, bodies: bodies));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<Directory> _workoutDir(
    String relDir,
    int workoutNumber, {
    bool create = true,
  }) async {
    final root = await _root();
    final dir = Directory('${root.path}/$relDir/$workoutNumber');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _root() async {
    final override = _rootOverride?.call();
    return override ?? await getApplicationSupportDirectory();
  }
}
