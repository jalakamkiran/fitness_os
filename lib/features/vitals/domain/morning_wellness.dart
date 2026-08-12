/// Hooper-4 morning wellness scores for one overnight sleep session.
///
/// Classic Hooper polarity: **1 = best / least symptom**, **7 = worst**.
/// Prefs may still hold legacy string feel values — those parse as incomplete.
class MorningWellness {
  const MorningWellness({
    required this.sleepQuality,
    required this.fatigue,
    required this.soreness,
    required this.stress,
    this.answeredAt,
    this.schema = 2,
  });

  static const minScore = 1;
  static const maxScore = 7;
  static const schemaVersion = 2;

  final int sleepQuality;
  final int fatigue;
  final int soreness;
  final int stress;
  final DateTime? answeredAt;
  final int schema;

  bool get isComplete =>
      _inRange(sleepQuality) &&
      _inRange(fatigue) &&
      _inRange(soreness) &&
      _inRange(stress);

  static bool _inRange(int value) =>
      value >= minScore && value <= maxScore;

  /// Returns a complete model, or null for legacy strings / incomplete / corrupt.
  static MorningWellness? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<Object?, Object?>.from(raw);
    final sleepQuality = _readScore(map['sleepQuality']);
    final fatigue = _readScore(map['fatigue']);
    final soreness = _readScore(map['soreness']);
    final stress = _readScore(map['stress']);
    if (sleepQuality == null ||
        fatigue == null ||
        soreness == null ||
        stress == null) {
      return null;
    }
    DateTime? answeredAt;
    final answeredRaw = map['answeredAt'];
    if (answeredRaw is String && answeredRaw.isNotEmpty) {
      answeredAt = DateTime.tryParse(answeredRaw);
    }
    final schemaRaw = map['schema'];
    final schema = schemaRaw is int
        ? schemaRaw
        : schemaRaw is num
            ? schemaRaw.toInt()
            : schemaVersion;
    return MorningWellness(
      sleepQuality: sleepQuality,
      fatigue: fatigue,
      soreness: soreness,
      stress: stress,
      answeredAt: answeredAt,
      schema: schema,
    );
  }

  static bool isCompleteRaw(Object? raw) => tryParse(raw) != null;

  static int? _readScore(Object? value) {
    final n = switch (value) {
      int v => v,
      num v => v.toInt(),
      _ => null,
    };
    if (n == null || !_inRange(n)) return null;
    return n;
  }

  Map<String, dynamic> toJson() => {
        'sleepQuality': sleepQuality,
        'fatigue': fatigue,
        'soreness': soreness,
        'stress': stress,
        'schema': schema,
        if (answeredAt != null) 'answeredAt': answeredAt!.toUtc().toIso8601String(),
      };

  MorningWellness copyWithAnsweredAt(DateTime answeredAt) => MorningWellness(
        sleepQuality: sleepQuality,
        fatigue: fatigue,
        soreness: soreness,
        stress: stress,
        answeredAt: answeredAt,
        schema: schema,
      );

  /// Redacted — never include score values (privacy).
  @override
  String toString() => 'MorningWellness(isComplete: $isComplete)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorningWellness &&
          sleepQuality == other.sleepQuality &&
          fatigue == other.fatigue &&
          soreness == other.soreness &&
          stress == other.stress &&
          answeredAt == other.answeredAt &&
          schema == other.schema;

  @override
  int get hashCode => Object.hash(
        sleepQuality,
        fatigue,
        soreness,
        stress,
        answeredAt,
        schema,
      );
}
