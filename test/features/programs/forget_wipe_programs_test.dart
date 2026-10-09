import 'dart:io';

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/programs/data/program_store.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Integration-style check that Programs wipe clears prefs + side files
/// (mirrors food forget wipe composition for the Programs slice).
void main() {
  test('Forget wipe clears programs index + side files + ledger', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tempRoot =
        await Directory.systemTemp.createTemp('forget_wipe_programs_');
    addTearDown(() async {
      try {
        if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
      } catch (_) {}
    });

    final store = ProgramStore(prefs: prefs, rootOverride: () => tempRoot);
    await store.activate(
      Program(
        id: 'wipe-me',
        intake: const ProgramIntake(
          goalDistanceM: 1200,
          horizonWeeks: 3,
          sessionsPerWeek: 3,
          poolOnlyAcknowledged: true,
        ),
        status: ProgramStatus.active,
        createdAtMs: 1,
        rulesPackVersion: '1.0.0',
        schemaVersion: Program.currentSchemaVersion,
        milestones: const [
          Milestone(
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
            programId: 'wipe-me',
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
      ),
    );
    await store.saveLedger(
      const ProgressLedger().appendXp(
        XpEvent(
          id: 'x1',
          atMs: 1,
          source: XpSource.baselineLocked,
          amount: 50,
          programId: 'wipe-me',
        ),
      ),
    );
    await prefs.setBool(GateAPrefs.programsHideGameLayer, true);

    // Simulated diagnostics_di programs slice of wipe body.
    await store.clearLocal();

    expect(prefs.containsKey(GateAPrefs.programsIndexJson), isFalse);
    expect(prefs.containsKey(GateAPrefs.programsLedgerJson), isFalse);
    expect(prefs.containsKey(GateAPrefs.programsHideGameLayer), isFalse);
    expect(await store.loadActive(), isNull);
    final dir = Directory('${tempRoot.path}/${GateAPrefs.programsDir}');
    expect(await dir.exists(), isFalse);
  });
}
