/// Session role within a week (from rules pack).
enum ChoreRole {
  endurance,
  quality,
  technique,
  recovery,
  proof,
  guidedTest,
  easy,
}

/// Athlete-facing chore lifecycle (habit layer).
enum ChoreState {
  scheduled,
  due,
  doneSynced,
  doneManual,
  adjusted,
  moved,
  skippedExcused,
  skippedOther,
  lapsed,
  superseded,
}

/// Excuse chip when skipping.
enum SkipReason {
  otherLoad,
  recovery,
  ill,
  travel,
  poolClosed,
  other,
}

/// One set block inside warm-up / main / cool-down.
class ChoreBlock {
  const ChoreBlock({
    required this.part,
    required this.label,
    required this.distanceM,
    this.restGuidanceSec,
    this.patternId,
    this.effortBand,
  });

  /// `warmUp` | `main` | `coolDown` | `technique` | `pre`.
  final String part;
  final String label;
  final int distanceM;
  final int? restGuidanceSec;
  final String? patternId;
  final String? effortBand;

  Map<String, dynamic> toJson() => {
        'part': part,
        'label': label,
        'distanceM': distanceM,
        if (restGuidanceSec != null) 'restGuidanceSec': restGuidanceSec,
        if (patternId != null) 'patternId': patternId,
        if (effortBand != null) 'effortBand': effortBand,
      };

  factory ChoreBlock.fromJson(Map<String, dynamic> json) {
    return ChoreBlock(
      part: json['part'] as String,
      label: json['label'] as String,
      distanceM: (json['distanceM'] as num).toInt(),
      restGuidanceSec: (json['restGuidanceSec'] as num?)?.toInt(),
      patternId: json['patternId'] as String?,
      effortBand: json['effortBand'] as String?,
    );
  }
}

/// One prescribed pool session (WU / main / CD).
class ChoreSession {
  const ChoreSession({
    required this.id,
    required this.programId,
    required this.dayIso,
    required this.role,
    required this.state,
    required this.blocks,
    required this.targetDistanceM,
    this.focusLine,
    this.milestoneId,
    this.matchedWorkoutNumber,
    this.matchedStartTime,
    this.skipReason,
    this.judgedDistanceM,
    this.judgedDurationSec,
    this.completedAtMs,
  });

  final String id;
  final String programId;
  final String dayIso;
  final ChoreRole role;
  final ChoreState state;
  final List<ChoreBlock> blocks;
  final int targetDistanceM;
  final String? focusLine;
  final String? milestoneId;
  final int? matchedWorkoutNumber;
  final int? matchedStartTime;
  final SkipReason? skipReason;
  final int? judgedDistanceM;
  final int? judgedDurationSec;
  final int? completedAtMs;

  bool get hasWuMainCd {
    final parts = blocks.map((b) => b.part).toSet();
    return parts.contains('warmUp') &&
        parts.contains('main') &&
        parts.contains('coolDown');
  }

  ChoreSession copyWith({
    String? id,
    String? programId,
    String? dayIso,
    ChoreRole? role,
    ChoreState? state,
    List<ChoreBlock>? blocks,
    int? targetDistanceM,
    String? focusLine,
    String? milestoneId,
    int? matchedWorkoutNumber,
    int? matchedStartTime,
    SkipReason? skipReason,
    int? judgedDistanceM,
    int? judgedDurationSec,
    int? completedAtMs,
  }) {
    return ChoreSession(
      id: id ?? this.id,
      programId: programId ?? this.programId,
      dayIso: dayIso ?? this.dayIso,
      role: role ?? this.role,
      state: state ?? this.state,
      blocks: blocks ?? this.blocks,
      targetDistanceM: targetDistanceM ?? this.targetDistanceM,
      focusLine: focusLine ?? this.focusLine,
      milestoneId: milestoneId ?? this.milestoneId,
      matchedWorkoutNumber: matchedWorkoutNumber ?? this.matchedWorkoutNumber,
      matchedStartTime: matchedStartTime ?? this.matchedStartTime,
      skipReason: skipReason ?? this.skipReason,
      judgedDistanceM: judgedDistanceM ?? this.judgedDistanceM,
      judgedDurationSec: judgedDurationSec ?? this.judgedDurationSec,
      completedAtMs: completedAtMs ?? this.completedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'programId': programId,
        'dayIso': dayIso,
        'role': role.name,
        'state': state.name,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'targetDistanceM': targetDistanceM,
        if (focusLine != null) 'focusLine': focusLine,
        if (milestoneId != null) 'milestoneId': milestoneId,
        if (matchedWorkoutNumber != null)
          'matchedWorkoutNumber': matchedWorkoutNumber,
        if (matchedStartTime != null) 'matchedStartTime': matchedStartTime,
        if (skipReason != null) 'skipReason': skipReason!.name,
        if (judgedDistanceM != null) 'judgedDistanceM': judgedDistanceM,
        if (judgedDurationSec != null) 'judgedDurationSec': judgedDurationSec,
        if (completedAtMs != null) 'completedAtMs': completedAtMs,
      };

  factory ChoreSession.fromJson(Map<String, dynamic> json) {
    return ChoreSession(
      id: json['id'] as String,
      programId: json['programId'] as String,
      dayIso: json['dayIso'] as String,
      role: ChoreRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => ChoreRole.endurance,
      ),
      state: ChoreState.values.firstWhere(
        (e) => e.name == json['state'],
        orElse: () => ChoreState.scheduled,
      ),
      blocks: (json['blocks'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ChoreBlock.fromJson)
          .toList(),
      targetDistanceM: (json['targetDistanceM'] as num).toInt(),
      focusLine: json['focusLine'] as String?,
      milestoneId: json['milestoneId'] as String?,
      matchedWorkoutNumber: (json['matchedWorkoutNumber'] as num?)?.toInt(),
      matchedStartTime: (json['matchedStartTime'] as num?)?.toInt(),
      skipReason: json['skipReason'] == null
          ? null
          : SkipReason.values.firstWhere(
              (e) => e.name == json['skipReason'],
              orElse: () => SkipReason.other,
            ),
      judgedDistanceM: (json['judgedDistanceM'] as num?)?.toInt(),
      judgedDurationSec: (json['judgedDurationSec'] as num?)?.toInt(),
      completedAtMs: (json['completedAtMs'] as num?)?.toInt(),
    );
  }
}
