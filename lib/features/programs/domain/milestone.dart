/// Lifecycle of a capacity/pace proof rung.
enum MilestoneStatus {
  upcoming,
  due,
  passed,
  nearPass,
  failed,
  delayed,
  paused,
  superseded,
}

/// One proof rung on the capacity (or pace) ladder.
class Milestone {
  const Milestone({
    required this.id,
    required this.index,
    required this.targetDistanceM,
    required this.plannedDateIso,
    required this.forecastDateIso,
    required this.status,
    this.targetPaceSecPer100,
    this.isPaceProof = false,
    this.passedAtIso,
    this.slipDays = 0,
    this.attemptCount = 0,
    this.notes,
  });

  final String id;
  final int index;
  final int targetDistanceM;
  final double? targetPaceSecPer100;
  final bool isPaceProof;

  /// Original planned proof day (YYYY-MM-DD local).
  final String plannedDateIso;

  /// Current forecast day after slips/pauses.
  final String forecastDateIso;
  final MilestoneStatus status;
  final String? passedAtIso;
  final int slipDays;
  final int attemptCount;
  final String? notes;

  Milestone copyWith({
    String? id,
    int? index,
    int? targetDistanceM,
    double? targetPaceSecPer100,
    bool? isPaceProof,
    String? plannedDateIso,
    String? forecastDateIso,
    MilestoneStatus? status,
    String? passedAtIso,
    int? slipDays,
    int? attemptCount,
    String? notes,
  }) {
    return Milestone(
      id: id ?? this.id,
      index: index ?? this.index,
      targetDistanceM: targetDistanceM ?? this.targetDistanceM,
      targetPaceSecPer100: targetPaceSecPer100 ?? this.targetPaceSecPer100,
      isPaceProof: isPaceProof ?? this.isPaceProof,
      plannedDateIso: plannedDateIso ?? this.plannedDateIso,
      forecastDateIso: forecastDateIso ?? this.forecastDateIso,
      status: status ?? this.status,
      passedAtIso: passedAtIso ?? this.passedAtIso,
      slipDays: slipDays ?? this.slipDays,
      attemptCount: attemptCount ?? this.attemptCount,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'index': index,
        'targetDistanceM': targetDistanceM,
        if (targetPaceSecPer100 != null)
          'targetPaceSecPer100': targetPaceSecPer100,
        'isPaceProof': isPaceProof,
        'plannedDateIso': plannedDateIso,
        'forecastDateIso': forecastDateIso,
        'status': status.name,
        if (passedAtIso != null) 'passedAtIso': passedAtIso,
        'slipDays': slipDays,
        'attemptCount': attemptCount,
        if (notes != null) 'notes': notes,
      };

  factory Milestone.fromJson(Map<String, dynamic> json) {
    return Milestone(
      id: json['id'] as String,
      index: (json['index'] as num).toInt(),
      targetDistanceM: (json['targetDistanceM'] as num).toInt(),
      targetPaceSecPer100: (json['targetPaceSecPer100'] as num?)?.toDouble(),
      isPaceProof: json['isPaceProof'] as bool? ?? false,
      plannedDateIso: json['plannedDateIso'] as String,
      forecastDateIso: json['forecastDateIso'] as String,
      status: MilestoneStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MilestoneStatus.upcoming,
      ),
      passedAtIso: json['passedAtIso'] as String?,
      slipDays: (json['slipDays'] as num?)?.toInt() ?? 0,
      attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
      notes: json['notes'] as String?,
    );
  }
}
