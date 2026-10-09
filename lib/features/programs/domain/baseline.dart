/// Confidence of a pool-swim baseline estimate.
enum BaselineConfidence {
  high,
  medium,
  low,
  insufficient,
}

/// Athlete-visible reason when history is thin or cascade falls through.
enum BaselineReason {
  richHistory,
  sparseHistory,
  emptyHistory,
  openWaterOnly,
  guidedTestRequired,
  selfReported,
  restHeavyUnconfirmed,
}

/// Continuous-distance capacity + optional CSS pace anchor for plan craft.
class Baseline {
  const Baseline({
    required this.capacityDistanceM,
    required this.confidence,
    required this.reason,
    this.cssPaceSecPer100,
    this.guidedTestRequired = false,
    this.selfReported = false,
    this.sourceWorkoutNumbers = const [],
  });

  final int capacityDistanceM;
  final double? cssPaceSecPer100;
  final BaselineConfidence confidence;
  final BaselineReason reason;
  final bool guidedTestRequired;
  final bool selfReported;
  final List<int> sourceWorkoutNumbers;

  Map<String, dynamic> toJson() => {
        'capacityDistanceM': capacityDistanceM,
        if (cssPaceSecPer100 != null) 'cssPaceSecPer100': cssPaceSecPer100,
        'confidence': confidence.name,
        'reason': reason.name,
        'guidedTestRequired': guidedTestRequired,
        'selfReported': selfReported,
        'sourceWorkoutNumbers': sourceWorkoutNumbers,
      };

  factory Baseline.fromJson(Map<String, dynamic> json) {
    return Baseline(
      capacityDistanceM: (json['capacityDistanceM'] as num?)?.toInt() ?? 0,
      cssPaceSecPer100: (json['cssPaceSecPer100'] as num?)?.toDouble(),
      confidence: BaselineConfidence.values.firstWhere(
        (e) => e.name == json['confidence'],
        orElse: () => BaselineConfidence.insufficient,
      ),
      reason: BaselineReason.values.firstWhere(
        (e) => e.name == json['reason'],
        orElse: () => BaselineReason.emptyHistory,
      ),
      guidedTestRequired: json['guidedTestRequired'] as bool? ?? false,
      selfReported: json['selfReported'] as bool? ?? false,
      sourceWorkoutNumbers: (json['sourceWorkoutNumbers'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
    );
  }
}
