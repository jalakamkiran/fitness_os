import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/program.dart';
import 'package:fitness_os/features/programs/domain/progress_ledger.dart';

/// How Home treats "today" for an active Agon (never uses next-open fallback).
enum HomeTodayKind {
  rest,
  choreOpen,
  proofOpen,
  done,
}

/// Result of [classifyHomeToday].
class HomeTodayClassification {
  const HomeTodayClassification({
    required this.kind,
    this.chore,
  });

  final HomeTodayKind kind;

  /// Today's chore when one exists (including completed).
  final ChoreSession? chore;
}

/// One planned Agon chore day in the current Mon–Sun week.
class WeekAdherenceSlot {
  const WeekAdherenceSlot({
    required this.dayIso,
    required this.choreId,
    required this.done,
    required this.isToday,
    required this.role,
  });

  final String dayIso;
  final String choreId;
  final bool done;
  final bool isToday;
  final ChoreRole role;
}

/// Week adherence + Home today classification (pure; no Flutter).
abstract final class HomeAgonDay {
  /// Classify today using chores whose [ChoreSession.dayIso] equals local today.
  ///
  /// Does **not** fall through to a future open chore (unlike
  /// [ProgramsController.todaysChore]).
  static HomeTodayClassification classifyHomeToday(
    Program program, {
    DateTime? now,
  }) {
    final when = now ?? DateTime.now();
    final todayIso = _isoDay(when);
    ChoreSession? todayChore;
    for (final c in program.chores) {
      if (c.dayIso == todayIso && c.state != ChoreState.superseded) {
        todayChore = c;
        break;
      }
    }
    if (todayChore == null) {
      return const HomeTodayClassification(kind: HomeTodayKind.rest);
    }
    if (_isDone(todayChore.state)) {
      return HomeTodayClassification(
        kind: HomeTodayKind.done,
        chore: todayChore,
      );
    }
    if (todayChore.role == ChoreRole.proof) {
      return HomeTodayClassification(
        kind: HomeTodayKind.proofOpen,
        chore: todayChore,
      );
    }
    return HomeTodayClassification(
      kind: HomeTodayKind.choreOpen,
      chore: todayChore,
    );
  }

  /// Planned Agon chore days this Mon–Sun week (no phantom sessionsPerWeek slots).
  static List<WeekAdherenceSlot> weekAdherenceSlots(
    Program program, {
    DateTime? now,
  }) {
    final when = now ?? DateTime.now();
    final weekKey = ProgressEngine.weekKeyFor(when);
    final todayIso = _isoDay(when);
    final slots = <WeekAdherenceSlot>[];

    for (final c in program.chores) {
      if (c.state == ChoreState.superseded) continue;
      final day = _tryParseIsoDay(c.dayIso);
      if (day == null) continue;
      if (ProgressEngine.weekKeyFor(day) != weekKey) continue;
      slots.add(
        WeekAdherenceSlot(
          dayIso: c.dayIso,
          choreId: c.id,
          done: _isDone(c.state),
          isToday: c.dayIso == todayIso,
          role: c.role,
        ),
      );
    }

    slots.sort((a, b) => a.dayIso.compareTo(b.dayIso));
    return slots;
  }

  /// True when the ledger has meaningful Odyssey history for idle snapshot.
  static bool hasOdysseySnapshot(ProgressLedger ledger) {
    if (ledger.xpEvents.isNotEmpty || ledger.choreEvents.isNotEmpty) {
      return true;
    }
    if (ledger.currentStreakWeeks > 0 || ledger.bestStreakWeeks > 0) {
      return true;
    }
    if (ledger.level > 1) return true;
    return false;
  }

  static bool _isDone(ChoreState state) {
    return state == ChoreState.doneSynced ||
        state == ChoreState.doneManual ||
        state == ChoreState.adjusted;
  }

  static String _isoDay(DateTime local) {
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? _tryParseIsoDay(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}
