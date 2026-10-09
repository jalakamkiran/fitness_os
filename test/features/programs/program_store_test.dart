import 'dart:io';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Program _sampleProgram({
  required String id,
  ProgramStatus status = ProgramStatus.active,
}) {
  return Program(
    id: id,
    intake: const ProgramIntake(
      goalDistanceM: 1200,
      horizonWeeks: 3,
      sessionsPerWeek: 3,
      poolOnlyAcknowledged: true,
    ),
    status: status,
    createdAtMs: 1,
    rulesPackVersion: '1.0.0',
    schemaVersion: Program.currentSchemaVersion,
    milestones: [
      const Milestone(
        id: 'm1',
        index: 0,
        targetDistanceM: 1200,
        plannedDateIso: '2026-10-20',
        forecastDateIso: '2026-10-20',
        status: MilestoneStatus.upcoming,
      ),
    ],
    chores: [
      ChoreSession(
        id: 'c1',
        programId: id,
        dayIso: '2026-10-10',
        role: ChoreRole.endurance,
        state: ChoreState.scheduled,
        targetDistanceM: 1800,
        blocks: const [
          ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 300),
          ChoreBlock(part: 'main', label: 'Main', distanceM: 1200),
          ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 200),
        ],
      ),
    ],
  );
}

void main() {
  late Directory tempRoot;
  late SharedPreferences prefs;
  late ProgramStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tempRoot = await Directory.systemTemp.createTemp('program_store_test_');
    store = ProgramStore(prefs: prefs, rootOverride: () => tempRoot);
  });

  tearDown(() async {
    try {
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    } catch (_) {}
  });

  test('activate → reload preserves milestones and chores', () async {
    final program = _sampleProgram(id: 'p1');
    await store.activate(program);

    final loaded = await store.loadActive();
    expect(loaded, isNotNull);
    expect(loaded!.id, 'p1');
    expect(loaded.milestones, hasLength(1));
    expect(loaded.milestones.first.targetDistanceM, 1200);
    expect(loaded.chores, hasLength(1));
    expect(loaded.chores.first.hasWuMainCd, isTrue);
    expect(loaded.status, ProgramStatus.active);
  });

  test('replace active archives prior; only one active', () async {
    await store.activate(_sampleProgram(id: 'p1'));
    await store.activate(_sampleProgram(id: 'p2'));

    final index = await store.loadIndex();
    final actives =
        index.where((e) => e.status == ProgramStatus.active).toList();
    expect(actives, hasLength(1));
    expect(actives.first.id, 'p2');

    final prior = await store.loadById('p1');
    expect(prior!.status, ProgramStatus.archived);
    expect(await store.loadActive(), isNotNull);
    expect((await store.loadActive())!.id, 'p2');
  });

  test('clearLocal wipes index, ledger, and side files', () async {
    await store.activate(_sampleProgram(id: 'p1'));
    await store.saveLedger(
      const ProgressLedger().appendXp(
        XpEvent(
          id: 'x1',
          atMs: 1,
          source: XpSource.baselineLocked,
          amount: 50,
        ),
      ),
    );
    expect(await store.loadActive(), isNotNull);

    await store.clearLocal();

    expect(await store.loadIndex(), isEmpty);
    expect(await store.loadActive(), isNull);
    expect((await store.loadLedger()).xpEvents, isEmpty);
    expect(prefs.containsKey(GateAPrefs.programsIndexJson), isFalse);
    expect(prefs.containsKey(GateAPrefs.programsLedgerJson), isFalse);
    final dir = Directory('${tempRoot.path}/${GateAPrefs.programsDir}');
    expect(await dir.exists(), isFalse);
  });

  test('corrupt index recovers to empty without crash', () async {
    await prefs.setString(GateAPrefs.programsIndexJson, '{not-json');
    expect(await store.loadIndex(), isEmpty);
    expect(await store.loadActive(), isNull);
  });

  test('corrupt program side file returns null', () async {
    await store.activate(_sampleProgram(id: 'p1'));
    final file =
        File('${tempRoot.path}/${GateAPrefs.programsDir}/p1.json');
    await file.writeAsString('!!!');
    expect(await store.loadById('p1'), isNull);
  });

  test('levelForXp follows 100 × min(level, 8) curve', () {
    expect(ProgressLedger.levelForXp(0), 1);
    expect(ProgressLedger.levelForXp(99), 1);
    expect(ProgressLedger.levelForXp(100), 2);
    expect(ProgressLedger.levelForXp(300), 3);
    expect(ProgressLedger.levelForXp(1500), 6);
  });
}
