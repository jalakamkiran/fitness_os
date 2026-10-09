import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';
import 'package:fitness_os/features/programs/domain/week_adherence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Week of Mon 2026-10-05 … Sun 2026-10-11
  final monday = DateTime(2026, 10, 5, 12);
  final wednesday = DateTime(2026, 10, 7, 12);
  final friday = DateTime(2026, 10, 9, 12);

  ChoreSession chore({
    required String id,
    required String dayIso,
    required ChoreState state,
    ChoreRole role = ChoreRole.endurance,
    String? milestoneId,
  }) {
    return ChoreSession(
      id: id,
      programId: 'prog_1',
      dayIso: dayIso,
      role: role,
      state: state,
      blocks: const [
        ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 200),
        ChoreBlock(part: 'main', label: 'Main', distanceM: 800),
        ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 200),
      ],
      targetDistanceM: 1200,
      milestoneId: milestoneId,
    );
  }

  Program program(List<ChoreSession> chores) {
    return Program(
      id: 'prog_1',
      intake: const ProgramIntake(
        goalDistanceM: 1200,
        horizonWeeks: 3,
        sessionsPerWeek: 3,
      ),
      status: ProgramStatus.active,
      createdAtMs: monday.millisecondsSinceEpoch,
      rulesPackVersion: 'v1',
      schemaVersion: Program.currentSchemaVersion,
      milestones: const [],
      chores: chores,
    );
  }

  group('weekAdherenceSlots', () {
    test('happy: Mon+Wed done, Fri pending → 2/3', () {
      final p = program([
        chore(
          id: 'c1',
          dayIso: '2026-10-05',
          state: ChoreState.doneSynced,
        ),
        chore(
          id: 'c2',
          dayIso: '2026-10-07',
          state: ChoreState.doneManual,
        ),
        chore(
          id: 'c3',
          dayIso: '2026-10-09',
          state: ChoreState.scheduled,
        ),
      ]);

      final slots = HomeAgonDay.weekAdherenceSlots(p, now: friday);
      expect(slots, hasLength(3));
      expect(slots.where((s) => s.done), hasLength(2));
      expect(slots.last.dayIso, '2026-10-09');
      expect(slots.last.done, isFalse);
      expect(slots.last.isToday, isTrue);
    });

    test('rest mid-week: no invented today slot', () {
      final p = program([
        chore(
          id: 'c1',
          dayIso: '2026-10-05',
          state: ChoreState.doneSynced,
        ),
        chore(
          id: 'c3',
          dayIso: '2026-10-09',
          state: ChoreState.scheduled,
        ),
      ]);

      final slots = HomeAgonDay.weekAdherenceSlots(p, now: wednesday);
      expect(slots, hasLength(2));
      expect(slots.any((s) => s.isToday), isFalse);
    });

    test('empty chores → empty slots', () {
      final slots = HomeAgonDay.weekAdherenceSlots(program([]), now: monday);
      expect(slots, isEmpty);
    });

    test('week rollover excludes prior week', () {
      final nextMonday = DateTime(2026, 10, 12, 12);
      final p = program([
        chore(
          id: 'c1',
          dayIso: '2026-10-05',
          state: ChoreState.doneSynced,
        ),
        chore(
          id: 'c2',
          dayIso: '2026-10-12',
          state: ChoreState.scheduled,
        ),
      ]);

      final slots = HomeAgonDay.weekAdherenceSlots(p, now: nextMonday);
      expect(slots, hasLength(1));
      expect(slots.single.dayIso, '2026-10-12');
    });

    test('superseded chores excluded', () {
      final p = program([
        chore(
          id: 'c1',
          dayIso: '2026-10-05',
          state: ChoreState.superseded,
        ),
        chore(
          id: 'c2',
          dayIso: '2026-10-05',
          state: ChoreState.doneSynced,
        ),
      ]);
      final slots = HomeAgonDay.weekAdherenceSlots(p, now: monday);
      expect(slots, hasLength(1));
      expect(slots.single.choreId, 'c2');
    });
  });

  group('classifyHomeToday', () {
    test('choreOpen for endurance today', () {
      final p = program([
        chore(
          id: 'c1',
          dayIso: '2026-10-07',
          state: ChoreState.due,
        ),
        chore(
          id: 'c2',
          dayIso: '2026-10-09',
          state: ChoreState.scheduled,
        ),
      ]);
      final c = HomeAgonDay.classifyHomeToday(p, now: wednesday);
      expect(c.kind, HomeTodayKind.choreOpen);
      expect(c.chore?.id, 'c1');
    });

    test('future open chore does not become today → rest', () {
      final p = program([
        chore(
          id: 'c2',
          dayIso: '2026-10-09',
          state: ChoreState.scheduled,
        ),
      ]);
      final c = HomeAgonDay.classifyHomeToday(p, now: wednesday);
      expect(c.kind, HomeTodayKind.rest);
      expect(c.chore, isNull);
    });

    test('proofOpen for proof role today', () {
      final p = program([
        chore(
          id: 'proof1',
          dayIso: '2026-10-07',
          state: ChoreState.due,
          role: ChoreRole.proof,
          milestoneId: 'ms1',
        ),
      ]);
      final c = HomeAgonDay.classifyHomeToday(p, now: wednesday);
      expect(c.kind, HomeTodayKind.proofOpen);
      expect(c.chore?.milestoneId, 'ms1');
    });

    test('done when today chore completed', () {
      final p = program([
        chore(
          id: 'c1',
          dayIso: '2026-10-07',
          state: ChoreState.doneSynced,
        ),
      ]);
      final c = HomeAgonDay.classifyHomeToday(p, now: wednesday);
      expect(c.kind, HomeTodayKind.done);
    });
  });

  group('hasOdysseySnapshot', () {
    test('fresh ledger → false', () {
      expect(HomeAgonDay.hasOdysseySnapshot(const ProgressLedger()), isFalse);
    });

    test('xp history → true', () {
      final ledger = const ProgressLedger().appendXp(
        XpEvent(
          id: 'xp1',
          atMs: 1,
          source: XpSource.baselineLocked,
          amount: 50,
        ),
      );
      expect(HomeAgonDay.hasOdysseySnapshot(ledger), isTrue);
    });

    test('streak weeks → true', () {
      expect(
        HomeAgonDay.hasOdysseySnapshot(
          const ProgressLedger(currentStreakWeeks: 2),
        ),
        isTrue,
      );
    });
  });
}
