import 'package:fitness_os/features/programs/domain/baseline.dart';
import 'package:fitness_os/features/programs/domain/chore_session.dart';
import 'package:fitness_os/features/programs/domain/milestone.dart';

/// Lifecycle of a training program.
enum ProgramStatus {
  drafting,
  awaitingBaseline,
  active,
  paused,
  completed,
  archived,
}

/// Intake answers that seed plan craft.
class ProgramIntake {
  const ProgramIntake({
    required this.goalDistanceM,
    required this.horizonWeeks,
    required this.sessionsPerWeek,
    this.targetTimeSec,
    this.poolOnlyAcknowledged = false,
  });

  final int goalDistanceM;
  final int? targetTimeSec;
  final int horizonWeeks;
  final int sessionsPerWeek;
  final bool poolOnlyAcknowledged;

  Map<String, dynamic> toJson() => {
        'goalDistanceM': goalDistanceM,
        if (targetTimeSec != null) 'targetTimeSec': targetTimeSec,
        'horizonWeeks': horizonWeeks,
        'sessionsPerWeek': sessionsPerWeek,
        'poolOnlyAcknowledged': poolOnlyAcknowledged,
      };

  factory ProgramIntake.fromJson(Map<String, dynamic> json) {
    return ProgramIntake(
      goalDistanceM: (json['goalDistanceM'] as num).toInt(),
      targetTimeSec: (json['targetTimeSec'] as num?)?.toInt(),
      horizonWeeks: (json['horizonWeeks'] as num).toInt(),
      sessionsPerWeek: (json['sessionsPerWeek'] as num).toInt(),
      poolOnlyAcknowledged: json['poolOnlyAcknowledged'] as bool? ?? false,
    );
  }
}

/// One active (or archived) pool-swim program snapshot.
class Program {
  const Program({
    required this.id,
    required this.intake,
    required this.status,
    required this.createdAtMs,
    required this.rulesPackVersion,
    required this.schemaVersion,
    required this.milestones,
    required this.chores,
    this.baseline,
    this.feasibilityWarning,
    this.goalForecastEarliestIso,
    this.goalForecastLikelyIso,
    this.goalForecastLatestIso,
    this.poolOnly = true,
    this.pausedAtMs,
    this.pauseDaysAccumulated = 0,
    this.activatedAtMs,
    this.archivedAtMs,
  });

  static const currentSchemaVersion = 1;

  final String id;
  final ProgramIntake intake;
  final ProgramStatus status;
  final int createdAtMs;
  final String rulesPackVersion;
  final int schemaVersion;
  final Baseline? baseline;
  final List<Milestone> milestones;
  final List<ChoreSession> chores;

  /// Athlete-visible pace-vs-horizon honesty line when set.
  final String? feasibilityWarning;
  final String? goalForecastEarliestIso;
  final String? goalForecastLikelyIso;
  final String? goalForecastLatestIso;
  final bool poolOnly;
  final int? pausedAtMs;
  final int pauseDaysAccumulated;
  final int? activatedAtMs;
  final int? archivedAtMs;

  Program copyWith({
    String? id,
    ProgramIntake? intake,
    ProgramStatus? status,
    int? createdAtMs,
    String? rulesPackVersion,
    int? schemaVersion,
    Baseline? baseline,
    List<Milestone>? milestones,
    List<ChoreSession>? chores,
    String? feasibilityWarning,
    String? goalForecastEarliestIso,
    String? goalForecastLikelyIso,
    String? goalForecastLatestIso,
    bool? poolOnly,
    int? pausedAtMs,
    int? pauseDaysAccumulated,
    int? activatedAtMs,
    int? archivedAtMs,
  }) {
    return Program(
      id: id ?? this.id,
      intake: intake ?? this.intake,
      status: status ?? this.status,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      rulesPackVersion: rulesPackVersion ?? this.rulesPackVersion,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      baseline: baseline ?? this.baseline,
      milestones: milestones ?? this.milestones,
      chores: chores ?? this.chores,
      feasibilityWarning: feasibilityWarning ?? this.feasibilityWarning,
      goalForecastEarliestIso:
          goalForecastEarliestIso ?? this.goalForecastEarliestIso,
      goalForecastLikelyIso:
          goalForecastLikelyIso ?? this.goalForecastLikelyIso,
      goalForecastLatestIso:
          goalForecastLatestIso ?? this.goalForecastLatestIso,
      poolOnly: poolOnly ?? this.poolOnly,
      pausedAtMs: pausedAtMs ?? this.pausedAtMs,
      pauseDaysAccumulated: pauseDaysAccumulated ?? this.pauseDaysAccumulated,
      activatedAtMs: activatedAtMs ?? this.activatedAtMs,
      archivedAtMs: archivedAtMs ?? this.archivedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'intake': intake.toJson(),
        'status': status.name,
        'createdAtMs': createdAtMs,
        'rulesPackVersion': rulesPackVersion,
        'schemaVersion': schemaVersion,
        if (baseline != null) 'baseline': baseline!.toJson(),
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'chores': chores.map((c) => c.toJson()).toList(),
        if (feasibilityWarning != null)
          'feasibilityWarning': feasibilityWarning,
        if (goalForecastEarliestIso != null)
          'goalForecastEarliestIso': goalForecastEarliestIso,
        if (goalForecastLikelyIso != null)
          'goalForecastLikelyIso': goalForecastLikelyIso,
        if (goalForecastLatestIso != null)
          'goalForecastLatestIso': goalForecastLatestIso,
        'poolOnly': poolOnly,
        if (pausedAtMs != null) 'pausedAtMs': pausedAtMs,
        'pauseDaysAccumulated': pauseDaysAccumulated,
        if (activatedAtMs != null) 'activatedAtMs': activatedAtMs,
        if (archivedAtMs != null) 'archivedAtMs': archivedAtMs,
      };

  factory Program.fromJson(Map<String, dynamic> json) {
    return Program(
      id: json['id'] as String,
      intake: ProgramIntake.fromJson(
        Map<String, dynamic>.from(json['intake'] as Map),
      ),
      status: ProgramStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ProgramStatus.drafting,
      ),
      createdAtMs: (json['createdAtMs'] as num).toInt(),
      rulesPackVersion: json['rulesPackVersion'] as String? ?? 'unknown',
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion,
      baseline: json['baseline'] == null
          ? null
          : Baseline.fromJson(
              Map<String, dynamic>.from(json['baseline'] as Map),
            ),
      milestones: (json['milestones'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Milestone.fromJson)
          .toList(),
      chores: (json['chores'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ChoreSession.fromJson)
          .toList(),
      feasibilityWarning: json['feasibilityWarning'] as String?,
      goalForecastEarliestIso: json['goalForecastEarliestIso'] as String?,
      goalForecastLikelyIso: json['goalForecastLikelyIso'] as String?,
      goalForecastLatestIso: json['goalForecastLatestIso'] as String?,
      poolOnly: json['poolOnly'] as bool? ?? true,
      pausedAtMs: (json['pausedAtMs'] as num?)?.toInt(),
      pauseDaysAccumulated:
          (json['pauseDaysAccumulated'] as num?)?.toInt() ?? 0,
      activatedAtMs: (json['activatedAtMs'] as num?)?.toInt(),
      archivedAtMs: (json['archivedAtMs'] as num?)?.toInt(),
    );
  }
}

/// Lean SharedPreferences index row (side file holds full program JSON).
class ProgramIndexEntry {
  const ProgramIndexEntry({
    required this.id,
    required this.status,
    required this.updatedAtMs,
    this.goalDistanceM,
  });

  final String id;
  final ProgramStatus status;
  final int updatedAtMs;
  final int? goalDistanceM;

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status.name,
        'updatedAtMs': updatedAtMs,
        if (goalDistanceM != null) 'goalDistanceM': goalDistanceM,
      };

  factory ProgramIndexEntry.fromJson(Map<String, dynamic> json) {
    return ProgramIndexEntry(
      id: json['id'] as String,
      status: ProgramStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ProgramStatus.archived,
      ),
      updatedAtMs: (json['updatedAtMs'] as num).toInt(),
      goalDistanceM: (json['goalDistanceM'] as num?)?.toInt(),
    );
  }
}
