import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Week of Mon 2026-10-05 … Sun 2026-10-11
  final monday = DateTime(2026, 10, 5, 12);
  final tuesday = DateTime(2026, 10, 6, 12);
  final wednesday = DateTime(2026, 10, 7, 12);

  ChoreSession chore({
    required String id,
    required String dayIso,
    required ChoreState state,
    SkipReason? skipReason,
    DateTime? at,
  }) {
    final when = at ?? monday;
    return ChoreSession(
      id: id,
      programId: 'prog_1',
      dayIso: dayIso,
      role: ChoreRole.endurance,
      state: state,
      blocks: const [
        ChoreBlock(part: 'warmUp', label: 'WU', distanceM: 200),
        ChoreBlock(part: 'main', label: 'Main', distanceM: 800),
        ChoreBlock(part: 'coolDown', label: 'CD', distanceM: 200),
      ],
      targetDistanceM: 1200,
      skipReason: skipReason,
      completedAtMs: when.millisecondsSinceEpoch,
    );
  }

  group('ProgressEngine helpers', () {
    test('weekKeyFor is Monday of local Mon–Sun week', () {
      expect(ProgressEngine.weekKeyFor(monday), '2026-10-05');
      expect(ProgressEngine.weekKeyFor(DateTime(2026, 10, 11)), '2026-10-05');
      expect(ProgressEngine.weekKeyFor(DateTime(2026, 10, 12)), '2026-10-12');
    });

    test('floorFor = ceil(sessionsPerWeek / 2)', () {
      expect(ProgressEngine.floorFor(1), 1);
      expect(ProgressEngine.floorFor(2), 1);
      expect(ProgressEngine.floorFor(3), 2);
      expect(ProgressEngine.floorFor(4), 2);
      expect(ProgressEngine.floorFor(5), 3);
    });

    test('levelForXp uses cost 100 × min(L, 8)', () {
      expect(ProgressLedger.levelForXp(0), 1);
      expect(ProgressLedger.levelForXp(99), 1);
      expect(ProgressLedger.levelForXp(100), 2);
      expect(ProgressLedger.levelForXp(300), 3);
      expect(ProgressLedger.levelForXp(600), 4);
    });
  });

  group('streak + XP', () {
    test('happy: 3× week, complete 2 → streak holds (floor)', () {
      var ledger = const ProgressLedger();
      final weekKey = ProgressEngine.weekKeyFor(monday);

      ledger = ProgressEngine.recordChoreCompletion(
        ledger,
        chore: chore(
          id: 'c1',
          dayIso: '2026-10-05',
          state: ChoreState.doneSynced,
          at: monday,
        ),
        sessionsPerWeek: 3,
        asOf: monday,
        structureMatched: true,
      );
      ledger = ProgressEngine.recordChoreCompletion(
        ledger,
        chore: chore(
          id: 'c2',
          dayIso: '2026-10-07',
          state: ChoreState.doneManual,
          at: wednesday,
        ),
        sessionsPerWeek: 3,
        asOf: wednesday,
      );

      expect(ProgressEngine.countFloorCompletions(ledger, weekKey), 2);
      expect(ProgressEngine.floorFor(3), 2);

      ledger = ProgressEngine.closeWeek(
        ledger,
        weekKey: weekKey,
        sessionsPerWeek: 3,
        prescribedCount: 3,
      );

      expect(ledger.currentStreakWeeks, 1);
      expect(ledger.bestStreakWeeks, 1);
      expect(ledger.restPasses, 2); // floor week, not full → no +pass
      expect(
        ledger.xpEvents.where((e) => e.source == XpSource.floorWeek).length,
        1,
      );
      expect(ledger.totalXp, greaterThan(0));
      // Synced 100+20 + manual 70 + floor 25
      expect(ledger.totalXp, 100 + 20 + 70 + 25);
    });

    test('edge: break streak → best persists; no negative XP', () {
      var ledger = const ProgressLedger(
        restPasses: 0,
        currentStreakWeeks: 4,
        bestStreakWeeks: 6,
      );
      final weekKey = ProgressEngine.weekKeyFor(monday);

      // Only one completion in a 3× week (below floor of 2).
      ledger = ProgressEngine.recordChoreCompletion(
        ledger,
        chore: chore(
          id: 'c1',
          dayIso: '2026-10-05',
          state: ChoreState.doneSynced,
          at: monday,
        ),
        sessionsPerWeek: 3,
        asOf: monday,
      );

      final xpBeforeClose = ledger.totalXp;
      ledger = ProgressEngine.closeWeek(
        ledger,
        weekKey: weekKey,
        sessionsPerWeek: 3,
        prescribedCount: 3,
      );

      expect(ledger.currentStreakWeeks, 0);
      expect(ledger.bestStreakWeeks, 6);
      expect(ledger.restPasses, 0);
      expect(ledger.totalXp, xpBeforeClose); // break adds 0 XP, never negative
      expect(ledger.xpEvents.every((e) => e.amount >= 0), isTrue);
    });

    test('rest pass auto-consumed below floor keeps streak', () {
      var ledger = const ProgressLedger(
        restPasses: 2,
        currentStreakWeeks: 3,
        bestStreakWeeks: 3,
      );
      final weekKey = ProgressEngine.weekKeyFor(monday);

      ledger = ProgressEngine.recordChoreCompletion(
        ledger,
        chore: chore(
          id: 'c1',
          dayIso: '2026-10-05',
          state: ChoreState.doneManual,
          at: monday,
        ),
        sessionsPerWeek: 3,
        asOf: monday,
      );

      ledger = ProgressEngine.closeWeek(
        ledger,
        weekKey: weekKey,
        sessionsPerWeek: 3,
        prescribedCount: 3,
      );

      expect(ledger.restPasses, 1);
      expect(ledger.currentStreakWeeks, 4);
      expect(ledger.bestStreakWeeks, 4);
    });

    test('excused week: no pass consume; streak neither advances nor breaks',
        () {
      var ledger = const ProgressLedger(
        restPasses: 2,
        currentStreakWeeks: 2,
        bestStreakWeeks: 5,
      );
      final weekKey = ProgressEngine.weekKeyFor(monday);

      ledger = ProgressEngine.closeWeek(
        ledger,
        weekKey: weekKey,
        sessionsPerWeek: 3,
        prescribedCount: 3,
        weekExcused: true,
      );

      expect(ledger.restPasses, 2);
      expect(ledger.currentStreakWeeks, 2);
      expect(ledger.bestStreakWeeks, 5);
    });

    test('full week grants full XP and +1 rest pass (cap 3)', () {
      var ledger = const ProgressLedger(restPasses: 2);
      final weekKey = ProgressEngine.weekKeyFor(monday);

      for (final entry in [
        (id: 'c1', day: '2026-10-05', at: monday),
        (id: 'c2', day: '2026-10-06', at: tuesday),
        (id: 'c3', day: '2026-10-07', at: wednesday),
      ]) {
        ledger = ProgressEngine.recordChoreCompletion(
          ledger,
          chore: chore(
            id: entry.id,
            dayIso: entry.day,
            state: ChoreState.doneSynced,
            at: entry.at,
          ),
          sessionsPerWeek: 3,
          asOf: entry.at,
        );
      }

      ledger = ProgressEngine.closeWeek(
        ledger,
        weekKey: weekKey,
        sessionsPerWeek: 3,
        prescribedCount: 3,
      );

      expect(ledger.restPasses, 3);
      expect(
        ledger.xpEvents.where((e) => e.source == XpSource.fullWeek).single.amount,
        XpTable.fullWeek,
      );
      expect(
        ledger.xpEvents.where((e) => e.source == XpSource.floorWeek),
        isEmpty,
      );
    });

    test('edge: proof fail grants attempt XP; level/streak untouched by fail',
        () {
      // Seed at L2 with room before L3 so +100 attempt does not level-up.
      const base = ProgressLedger(
        currentStreakWeeks: 2,
        bestStreakWeeks: 2,
        restPasses: 2,
        xpEvents: [
          XpEvent(
            id: 'seed',
            atMs: 1,
            source: XpSource.baselineLocked,
            amount: 100,
          ),
        ],
      );
      expect(base.level, 2);
      final streakBefore = base.currentStreakWeeks;

      final afterFail = ProgressEngine.recordProofAttempt(
        base,
        passed: false,
        programId: 'prog_1',
        milestoneId: 'ms_0',
        asOf: monday,
      );

      expect(
        afterFail.xpEvents.where((e) => e.source == XpSource.proofAttempted),
        hasLength(1),
      );
      expect(
        afterFail.xpEvents.where((e) => e.source == XpSource.proofPassed),
        isEmpty,
      );
      expect(afterFail.totalXp, 100 + XpTable.proofAttempted);
      expect(afterFail.currentStreakWeeks, streakBefore);
      expect(afterFail.bestStreakWeeks, base.bestStreakWeeks);
      expect(afterFail.level, 2); // fail adds attempt XP only; no penalty

      final afterPass = ProgressEngine.recordProofAttempt(
        base,
        passed: true,
        programId: 'prog_1',
        milestoneId: 'ms_0',
        asOf: monday,
      );
      expect(afterPass.totalXp, 100 + 100 + 200);
      expect(afterPass.currentStreakWeeks, streakBefore);
    });

    test('AE4 spirit: excused/other skip records ledger only — no negative XP',
        () {
      var ledger = const ProgressLedger();

      ledger = ProgressEngine.recordChoreCompletion(
        ledger,
        chore: chore(
          id: 'c_excused',
          dayIso: '2026-10-05',
          state: ChoreState.skippedExcused,
          skipReason: SkipReason.otherLoad,
          at: monday,
        ),
        sessionsPerWeek: 3,
        asOf: monday,
      );
      ledger = ProgressEngine.recordChoreCompletion(
        ledger,
        chore: chore(
          id: 'c_other',
          dayIso: '2026-10-06',
          state: ChoreState.skippedOther,
          skipReason: SkipReason.other,
          at: tuesday,
        ),
        sessionsPerWeek: 3,
        asOf: tuesday,
      );

      expect(ledger.choreEvents, hasLength(2));
      expect(ledger.choreEvents[0].state, ChoreState.skippedExcused.name);
      expect(ledger.choreEvents[1].state, ChoreState.skippedOther.name);
      // otherLoad excused → no recovery bonus; other skip → 0 XP
      expect(ledger.totalXp, 0);
      expect(ledger.xpEvents.every((e) => e.amount >= 0), isTrue);
      // Ledger does not carry milestone slip fields — chore events only.
      expect(ledger.currentStreakWeeks, 0);
    });

    test('positive-only: appendXp clamps negatives to zero', () {
      final ledger = const ProgressLedger().appendXp(
        const XpEvent(
          id: 'bad',
          atMs: 1,
          source: XpSource.choreDoneManual,
          amount: -50,
        ),
      );
      expect(ledger.totalXp, 0);
      expect(ledger.xpEvents.single.amount, 0);
    });
  });
}
