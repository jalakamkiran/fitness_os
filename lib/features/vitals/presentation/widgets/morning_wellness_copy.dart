import 'package:fitness_os/features/vitals/domain/morning_wellness.dart';

/// Neutral athlete labels for Hooper-4 dimensions (classic polarity 1→7).
abstract final class MorningWellnessCopy {
  static const dimensions = <({
    String key,
    String title,
    String lowLabel,
    String highLabel,
  })>[
    (
      key: 'sleepQuality',
      title: 'Sleep quality',
      lowLabel: 'Very good',
      highLabel: 'Very poor',
    ),
    (
      key: 'fatigue',
      title: 'Fatigue',
      lowLabel: 'Very low',
      highLabel: 'Very high',
    ),
    (
      key: 'soreness',
      title: 'Muscle soreness',
      lowLabel: 'Very low',
      highLabel: 'Very high',
    ),
    (
      key: 'stress',
      title: 'Stress',
      lowLabel: 'Very low',
      highLabel: 'Very high',
    ),
  ];

  static int? scoreFor(MorningWellness w, String key) => switch (key) {
        'sleepQuality' => w.sleepQuality,
        'fatigue' => w.fatigue,
        'soreness' => w.soreness,
        'stress' => w.stress,
        _ => null,
      };

  static String endpointFor(String key, int score) {
    final dim = dimensions.firstWhere((d) => d.key == key);
    if (score <= 1) return dim.lowLabel;
    if (score >= 7) return dim.highLabel;
    return '$score';
  }

  static String detailLine(String key, int score) {
    final dim = dimensions.firstWhere((d) => d.key == key);
    final tip = score <= 2
        ? dim.lowLabel
        : score >= 6
            ? dim.highLabel
            : null;
    return tip == null ? '${dim.title} · $score' : '${dim.title} · $score · $tip';
  }
}
