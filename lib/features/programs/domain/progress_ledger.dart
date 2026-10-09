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
