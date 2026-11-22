class StrengthSet {
  StrengthSet({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.exercise,
    required this.setIndex,
    required this.plannedKg,
    required this.plannedReps,
    required this.actualKg,
    required this.actualReps,
    required this.failed,
    required this.notifiedAtMs,
    required this.loggedAtMs,
    required this.source,
    this.replyText,
    this.unknownReply = false,
    this.workoutNumber,
    this.timedOut = false,
    this.skipped = false,
  });

  final String id;
  final String sessionId;
  final String exerciseId;
  final String exercise;
  final int setIndex;
  final double plannedKg;
  final int plannedReps;
  final double actualKg;
  final int actualReps;
  final bool failed;
  final String? replyText;
  final bool unknownReply;
  final int notifiedAtMs;
  final int loggedAtMs;
  final String source;
  final int? workoutNumber;
  final bool timedOut;
  final bool skipped;

  static String idFor({
    required String sessionId,
    required String exerciseId,
    required int setIndex,
  }) =>
      '${sessionId}_${exerciseId}_$setIndex';

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'exerciseId': exerciseId,
        'exercise': exercise,
        'setIndex': setIndex,
        'plannedKg': plannedKg,
        'plannedReps': plannedReps,
        'actualKg': actualKg,
        'actualReps': actualReps,
        'failed': failed,
        if (replyText != null) 'replyText': replyText,
        'unknownReply': unknownReply,
        'notifiedAtMs': notifiedAtMs,
        'loggedAtMs': loggedAtMs,
        'source': source,
        if (workoutNumber != null) 'workoutNumber': workoutNumber,
      };

  factory StrengthSet.fromJson(Map<String, dynamic> json) => StrengthSet(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        exerciseId: json['exerciseId'] as String,
        exercise: json['exercise'] as String,
        setIndex: json['setIndex'] as int,
        plannedKg: (json['plannedKg'] as num).toDouble(),
        plannedReps: json['plannedReps'] as int,
        actualKg: (json['actualKg'] as num).toDouble(),
        actualReps: json['actualReps'] as int,
        failed: json['failed'] as bool? ?? false,
        replyText: json['replyText'] as String?,
        unknownReply: json['unknownReply'] as bool? ?? false,
        notifiedAtMs: json['notifiedAtMs'] as int,
        loggedAtMs: json['loggedAtMs'] as int,
        source: json['source'] as String,
        workoutNumber: json['workoutNumber'] as int?,
        timedOut: json['timedOut'] as bool? ?? false,
        skipped: json['skipped'] as bool? ?? false,
      );

  StrengthSet copyWith({
    double? actualKg,
    int? actualReps,
    bool? failed,
    String? replyText,
    bool? unknownReply,
    int? loggedAtMs,
    String? source,
    int? workoutNumber,
    bool? timedOut,
    bool? skipped,
  }) =>
      StrengthSet(
        id: id,
        sessionId: sessionId,
        exerciseId: exerciseId,
        exercise: exercise,
        setIndex: setIndex,
        plannedKg: plannedKg,
        plannedReps: plannedReps,
        actualKg: actualKg ?? this.actualKg,
        actualReps: actualReps ?? this.actualReps,
        failed: failed ?? this.failed,
        replyText: replyText ?? this.replyText,
        unknownReply: unknownReply ?? this.unknownReply,
        notifiedAtMs: notifiedAtMs,
        loggedAtMs: loggedAtMs ?? this.loggedAtMs,
        source: source ?? this.source,
        workoutNumber: workoutNumber ?? this.workoutNumber,
        timedOut: timedOut ?? this.timedOut,
        skipped: skipped ?? this.skipped,
      );
}