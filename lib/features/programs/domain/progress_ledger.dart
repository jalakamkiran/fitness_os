import 'package:fitness_os/features/programs/domain/chore_session.dart';

/// Append-only XP receipt (never negative).
enum XpSource {
  baselineLocked,
  guidedTestCompleted,
  choreDoneSynced,
  choreStructureBonus,
  choreDoneManual,
  choreAdjusted,
  excusedRecoveryBonus,
  floorWeek,
  fullWeek,
  proofAttempted,
  proofPassed,
  longestContinuousPb,
  comeback,
}

class XpEvent {
  const XpEvent({
    required this.id,
    required this.atMs,
    required this.source,
    required this.amount,
    this.programId,
    this.choreId,
    this.milestoneId,
    this.note,
  });

  final String id;
  final int atMs;
  final XpSource source;
  final int amount;
  final String? programId;
  final String? choreId;
  final String? milestoneId;
  final String? note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'atMs': atMs,
        'source': source.name,
        'amount': amount,
        if (programId != null) 'programId': programId,
        if (choreId != null) 'choreId': choreId,
        if (milestoneId != null) 'milestoneId': milestoneId,
        if (note != null) 'note': note,
      };

  factory XpEvent.fromJson(Map<String, dynamic> json) {
    return XpEvent(
      id: json['id'] as String,
      atMs: (json['atMs'] as num).toInt(),
      source: XpSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => XpSource.choreDoneManual,
      ),
      amount: (json['amount'] as num).toInt().clamp(0, 100000),
      programId: json['programId'] as String?,
      choreId: json['choreId'] as String?,
      milestoneId: json['milestoneId'] as String?,
      note: json['note'] as String?,
    );
  }
}

/// Append-only chore outcome for streak/scorecard derivation.
class ChoreEvent {
  const ChoreEvent({
    required this.id,
    required this.atMs,
    required this.programId,
    required this.choreId,
    required this.dayIso,
    required this.state,
    this.skipReason,
    this.weekKey,
  });

  final String id;
  final int atMs;
  final String programId;
  final String choreId;
  final String dayIso;

  /// Serialized [ChoreState.name].
  final String state;
  final String? skipReason;

  /// Mon–Sun week key YYYY-Www (ISO week) or local Mon-start key.
  final String? weekKey;

  Map<String, dynamic> toJson() => {
        'id': id,
        'atMs': atMs,
        'programId': programId,
        'choreId': choreId,
        'dayIso': dayIso,
        'state': state,
        if (skipReason != null) 'skipReason': skipReason,
        if (weekKey != null) 'weekKey': weekKey,
      };

  factory ChoreEvent.fromJson(Map<String, dynamic> json) {
    return ChoreEvent(
      id: json['id'] as String,
      atMs: (json['atMs'] as num).toInt(),
      programId: json['programId'] as String,
      choreId: json['choreId'] as String,
      dayIso: json['dayIso'] as String,
      state: json['state'] as String,
      skipReason: json['skipReason'] as String?,
      weekKey: json['weekKey'] as String?,
    );
  }
}

/// Lifetime progress blob (XP ledger + streak derivation inputs).
class ProgressLedger {
  const ProgressLedger({
    this.xpEvents = const [],
    this.choreEvents = const [],
    this.restPasses = 2,
    this.currentStreakWeeks = 0,
    this.bestStreakWeeks = 0,
    this.hideGameLayer = false,
  });

  final List<XpEvent> xpEvents;
  final List<ChoreEvent> choreEvents;
  final int restPasses;
  final int currentStreakWeeks;
  final int bestStreakWeeks;
  final bool hideGameLayer;

  int get totalXp =>
      xpEvents.fold<int>(0, (sum, e) => sum + (e.amount < 0 ? 0 : e.amount));

  /// Level from cumulative XP: cost L→L+1 = 100 × min(L, 8).
  static int levelForXp(int xp) {
    var remaining = xp < 0 ? 0 : xp;
    var level = 1;
    while (true) {
      final cost = 100 * (level < 8 ? level : 8);
      if (remaining < cost) return level;
      remaining -= cost;
      level += 1;
      if (level > 100) return level;
    }
  }

  int get level => levelForXp(totalXp);

  ProgressLedger copyWith({
    List<XpEvent>? xpEvents,
    List<ChoreEvent>? choreEvents,
    int? restPasses,
    int? currentStreakWeeks,
    int? bestStreakWeeks,
    bool? hideGameLayer,
  }) {
    return ProgressLedger(
      xpEvents: xpEvents ?? this.xpEvents,
      choreEvents: choreEvents ?? this.choreEvents,
      restPasses: restPasses ?? this.restPasses,
      currentStreakWeeks: currentStreakWeeks ?? this.currentStreakWeeks,
      bestStreakWeeks: bestStreakWeeks ?? this.bestStreakWeeks,
      hideGameLayer: hideGameLayer ?? this.hideGameLayer,
    );
  }

  ProgressLedger appendXp(XpEvent event) {
    final amount = event.amount < 0 ? event.copyWithAmount(0) : event;
    return copyWith(xpEvents: [...xpEvents, amount]);
  }

  ProgressLedger appendChore(ChoreEvent event) {
    return copyWith(choreEvents: [...choreEvents, event]);
  }

  Map<String, dynamic> toJson() => {
        'xpEvents': xpEvents.map((e) => e.toJson()).toList(),
        'choreEvents': choreEvents.map((e) => e.toJson()).toList(),
        'restPasses': restPasses,
        'currentStreakWeeks': currentStreakWeeks,
        'bestStreakWeeks': bestStreakWeeks,
        'hideGameLayer': hideGameLayer,
      };

  factory ProgressLedger.fromJson(Map<String, dynamic> json) {
    return ProgressLedger(
      xpEvents: (json['xpEvents'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(XpEvent.fromJson)
          .toList(),
      choreEvents: (json['choreEvents'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ChoreEvent.fromJson)
          .toList(),
      restPasses: (json['restPasses'] as num?)?.toInt() ?? 2,
      currentStreakWeeks: (json['currentStreakWeeks'] as num?)?.toInt() ?? 0,
      bestStreakWeeks: (json['bestStreakWeeks'] as num?)?.toInt() ?? 0,
      hideGameLayer: json['hideGameLayer'] as bool? ?? false,
    );
  }
}

extension on XpEvent {
  XpEvent copyWithAmount(int amount) => XpEvent(
        id: id,
        atMs: atMs,
        source: source,
        amount: amount,
        programId: programId,
        choreId: choreId,
        milestoneId: milestoneId,
        note: note,
      );
}

/// XP table constants (gamification research §6.3) — single tune point.
abstract final class XpTable {
  static const baselineLocked = 50;
  static const guidedTestCompleted = 100;
  static const choreDoneSynced = 100;
  static const choreStructureBonus = 20;
  static const choreDoneManual = 70;
  static const choreAdjusted = 60;
  static const excusedRecoveryBonus = 25;
  static const floorWeek = 25;
  static const fullWeek = 50;
  static const proofAttempted = 100;
  static const proofPassed = 200;
  static const longestContinuousPb = 100;
  static const comeback = 50;

  static int forSource(XpSource source) {
    switch (source) {
      case XpSource.baselineLocked:
        return baselineLocked;
      case XpSource.guidedTestCompleted:
        return guidedTestCompleted;
      case XpSource.choreDoneSynced:
        return choreDoneSynced;
      case XpSource.choreStructureBonus:
        return choreStructureBonus;
      case XpSource.choreDoneManual:
        return choreDoneManual;
      case XpSource.choreAdjusted:
        return choreAdjusted;
      case XpSource.excusedRecoveryBonus:
        return excusedRecoveryBonus;
      case XpSource.floorWeek:
        return floorWeek;
      case XpSource.fullWeek:
        return fullWeek;
      case XpSource.proofAttempted:
        return proofAttempted;
      case XpSource.proofPassed:
        return proofPassed;
      case XpSource.longestContinuousPb:
        return longestContinuousPb;
      case XpSource.comeback:
        return comeback;
    }
  }
}

/// Weekly streak / XP mutation helpers over an append-only [ProgressLedger].
///
/// Streaks are Mon–Sun local. Floor = ceil(sessionsPerWeek / 2). Rest Passes
/// start at 2, +1 per full week (cap 3). XP is positive-only; proofs never
/// break streaks.
abstract final class ProgressEngine {
  static const int restPassStart = 2;
  static const int restPassCap = 3;
  static const int comebackIdleDays = 7;
  static const int comebackCooldownDays = 21;

  /// Local Mon–Sun week key: ISO date of that week's Monday (`YYYY-MM-DD`).
  static String weekKeyFor(DateTime local) {
    final day = DateTime(local.year, local.month, local.day);
    final monday = day.subtract(Duration(days: day.weekday - DateTime.monday));
    final y = monday.year.toString().padLeft(4, '0');
    final m = monday.month.toString().padLeft(2, '0');
    final d = monday.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Floor sessions that keep a weekly streak: `ceil(sessionsPerWeek / 2)`.
  static int floorFor(int sessionsPerWeek) {
    final n = sessionsPerWeek < 1 ? 1 : sessionsPerWeek;
    return (n + 1) ~/ 2;
  }

  /// True when [state] counts toward the weekly floor.
  static bool countsForFloor(String state) {
    return state == ChoreState.doneSynced.name ||
        state == ChoreState.doneManual.name ||
        state == ChoreState.adjusted.name;
  }

  /// Append a chore outcome + positive XP; does not close the week / streak.
  static ProgressLedger recordChoreCompletion(
    ProgressLedger ledger, {
    required ChoreSession chore,
    required int sessionsPerWeek,
    DateTime? asOf,
    bool structureMatched = false,
  }) {
    // [sessionsPerWeek] is accepted so callers can share the intake context
    // used later by [closeWeek]; chore XP itself is state-driven.
    final _ = sessionsPerWeek;

    final when = asOf ??
        (chore.completedAtMs != null
            ? DateTime.fromMillisecondsSinceEpoch(chore.completedAtMs!)
            : DateTime.now());
    final atMs = when.millisecondsSinceEpoch;
    final weekKey = weekKeyFor(when);

    var next = ledger.appendChore(
      ChoreEvent(
        id: 'chore_${chore.id}_$atMs',
        atMs: atMs,
        programId: chore.programId,
        choreId: chore.id,
        dayIso: chore.dayIso,
        state: chore.state.name,
        skipReason: chore.skipReason?.name,
        weekKey: weekKey,
      ),
    );

    final xpBits = <XpEvent>[];
    void addXp(XpSource source, {String? note, String? milestoneId}) {
      final amount = XpTable.forSource(source);
      if (amount <= 0) return;
      xpBits.add(
        XpEvent(
          id: 'xp_${source.name}_${chore.id}_$atMs${note ?? ''}',
          atMs: atMs,
          source: source,
          amount: amount,
          programId: chore.programId,
          choreId: chore.id,
          milestoneId: milestoneId ?? chore.milestoneId,
          note: note,
        ),
      );
    }

    switch (chore.state) {
      case ChoreState.doneSynced:
        if (!_hasChoreXpOnDay(next, chore.dayIso)) {
          addXp(XpSource.choreDoneSynced);
          if (structureMatched) {
            addXp(XpSource.choreStructureBonus);
          }
        }
        break;
      case ChoreState.doneManual:
        if (!_hasChoreXpOnDay(next, chore.dayIso)) {
          addXp(XpSource.choreDoneManual);
        }
        break;
      case ChoreState.adjusted:
        if (!_hasChoreXpOnDay(next, chore.dayIso)) {
          addXp(XpSource.choreAdjusted);
        }
        break;
      case ChoreState.skippedExcused:
        if (chore.skipReason == SkipReason.recovery &&
            !_hasRecoveryBonusInWeek(next, weekKey)) {
          addXp(XpSource.excusedRecoveryBonus, note: 'close:$weekKey:recovery');
        }
        break;
      case ChoreState.scheduled:
      case ChoreState.due:
      case ChoreState.moved:
      case ChoreState.skippedOther:
      case ChoreState.lapsed:
      case ChoreState.superseded:
        break;
    }

    if (_isCompletionState(chore.state) && _qualifiesForComeback(next, when)) {
      addXp(XpSource.comeback, note: 'comeback');
    }

    for (final e in xpBits) {
      next = next.appendXp(e);
    }
    return next;
  }

  /// Proof attempt XP (+100); +200 more if passed. Never touches streak.
  static ProgressLedger recordProofAttempt(
    ProgressLedger ledger, {
    required bool passed,
    String? programId,
    String? milestoneId,
    DateTime? asOf,
  }) {
    final when = asOf ?? DateTime.now();
    final atMs = when.millisecondsSinceEpoch;
    var next = ledger.appendXp(
      XpEvent(
        id: 'xp_proof_attempt_${milestoneId ?? 'x'}_$atMs',
        atMs: atMs,
        source: XpSource.proofAttempted,
        amount: XpTable.proofAttempted,
        programId: programId,
        milestoneId: milestoneId,
      ),
    );
    if (passed) {
      next = next.appendXp(
        XpEvent(
          id: 'xp_proof_passed_${milestoneId ?? 'x'}_$atMs',
          atMs: atMs,
          source: XpSource.proofPassed,
          amount: XpTable.proofPassed,
          programId: programId,
          milestoneId: milestoneId,
        ),
      );
    }
    return next;
  }

  /// Evaluate a Mon–Sun week: floor / full / rest-pass / break / excused.
  ///
  /// Idempotent per [weekKey] (tracked via XP note `close:$weekKey`).
  static ProgressLedger closeWeek(
    ProgressLedger ledger, {
    required String weekKey,
    required int sessionsPerWeek,
    required int prescribedCount,
    bool weekExcused = false,
  }) {
    if (_weekAlreadyClosed(ledger, weekKey)) return ledger;

    final completed = countFloorCompletions(ledger, weekKey);
    final floor = floorFor(sessionsPerWeek);
    final prescribed = prescribedCount < 0 ? 0 : prescribedCount;
    final atMs = DateTime.now().millisecondsSinceEpoch;
    final closeNote = 'close:$weekKey';

    if (weekExcused) {
      // Excused: free — no pass, streak neither advances nor breaks.
      return ledger.appendXp(
        XpEvent(
          id: 'xp_week_excused_$weekKey',
          atMs: atMs,
          source: XpSource.floorWeek,
          amount: 0,
          note: closeNote,
        ),
      );
    }

    if (completed >= floor) {
      final full = prescribed > 0 && completed >= prescribed;
      final nextStreak = ledger.currentStreakWeeks + 1;
      final best = nextStreak > ledger.bestStreakWeeks
          ? nextStreak
          : ledger.bestStreakWeeks;
      var passes = ledger.restPasses;
      if (full) {
        passes = (passes + 1).clamp(0, restPassCap);
      }
      return ledger
          .copyWith(
            currentStreakWeeks: nextStreak,
            bestStreakWeeks: best,
            restPasses: passes,
          )
          .appendXp(
            XpEvent(
              id: 'xp_week_${full ? 'full' : 'floor'}_$weekKey',
              atMs: atMs,
              source: full ? XpSource.fullWeek : XpSource.floorWeek,
              amount: full ? XpTable.fullWeek : XpTable.floorWeek,
              note: closeNote,
            ),
          );
    }

    // Below floor: auto-consume a Rest Pass if available.
    if (ledger.restPasses > 0) {
      final nextStreak = ledger.currentStreakWeeks + 1;
      final best = nextStreak > ledger.bestStreakWeeks
          ? nextStreak
          : ledger.bestStreakWeeks;
      return ledger
          .copyWith(
            restPasses: ledger.restPasses - 1,
            currentStreakWeeks: nextStreak,
            bestStreakWeeks: best,
          )
          .appendXp(
            XpEvent(
              id: 'xp_week_pass_$weekKey',
              atMs: atMs,
              source: XpSource.floorWeek,
              amount: 0,
              note: closeNote,
            ),
          );
    }

    // Break: current → 0, best persists, no negative XP.
    return ledger
        .copyWith(currentStreakWeeks: 0)
        .appendXp(
          XpEvent(
            id: 'xp_week_break_$weekKey',
            atMs: atMs,
            source: XpSource.floorWeek,
            amount: 0,
            note: closeNote,
          ),
        );
  }

  /// Floor-counting completions in [weekKey] (unique chore ids).
  static int countFloorCompletions(ProgressLedger ledger, String weekKey) {
    final ids = <String>{};
    for (final e in ledger.choreEvents) {
      if (e.weekKey != weekKey) continue;
      if (!countsForFloor(e.state)) continue;
      ids.add(e.choreId);
    }
    return ids.length;
  }

  static bool _weekAlreadyClosed(ProgressLedger ledger, String weekKey) {
    final marker = 'close:$weekKey';
    return ledger.xpEvents.any((e) => e.note == marker);
  }

  static bool _isCompletionState(ChoreState state) {
    return state == ChoreState.doneSynced ||
        state == ChoreState.doneManual ||
        state == ChoreState.adjusted;
  }

  static bool _hasChoreXpOnDay(ProgressLedger ledger, String dayIso) {
    const choreSources = {
      XpSource.choreDoneSynced,
      XpSource.choreDoneManual,
      XpSource.choreAdjusted,
    };
    final paidChoreIds = ledger.xpEvents
        .where((e) => choreSources.contains(e.source))
        .map((e) => e.choreId)
        .whereType<String>()
        .toSet();
    if (paidChoreIds.isEmpty) return false;
    for (final c in ledger.choreEvents) {
      if (c.dayIso == dayIso && paidChoreIds.contains(c.choreId)) {
        return true;
      }
    }
    return false;
  }

  static bool _hasRecoveryBonusInWeek(ProgressLedger ledger, String weekKey) {
    return ledger.xpEvents.any(
      (e) =>
          e.source == XpSource.excusedRecoveryBonus &&
          (e.note?.contains(weekKey) ?? false),
    );
  }

  static bool _qualifiesForComeback(ProgressLedger ledger, DateTime when) {
    final completions = ledger.choreEvents
        .where((e) => countsForFloor(e.state))
        .toList();
    // Exclude the event just appended (last one) when checking idle gap.
    if (completions.length < 2) {
      // First-ever completion is not a comeback.
      return false;
    }
    final prior = completions[completions.length - 2];
    final gap = when.difference(
      DateTime.fromMillisecondsSinceEpoch(prior.atMs),
    );
    if (gap.inDays < comebackIdleDays) return false;

    final cutoff = when.subtract(const Duration(days: comebackCooldownDays));
    final recentComeback = ledger.xpEvents.any(
      (e) =>
          e.source == XpSource.comeback &&
          e.atMs >= cutoff.millisecondsSinceEpoch,
    );
    return !recentComeback;
  }
}
