import 'package:fitness_os/core/huawei/huawei_link.dart';

/// Local calendar day keys (`yyyy-MM-dd`) covering `[beginUnix, endUnix]`.
///
/// Overnight spans that cross midnight return both dayKeys. Inverted or empty
/// ranges return an empty list.
List<String> sleepHrDayKeys({
  required int beginUnix,
  required int endUnix,
}) {
  if (beginUnix <= 0 || endUnix <= beginUnix) return const [];
  final begin = DateTime.fromMillisecondsSinceEpoch(beginUnix * 1000);
  final end = DateTime.fromMillisecondsSinceEpoch(endUnix * 1000);
  final keys = <String>[];
  var cursor = DateTime(begin.year, begin.month, begin.day);
  final last = DateTime(end.year, end.month, end.day);
  while (!cursor.isAfter(last)) {
    keys.add(_dayKey(cursor));
    cursor = cursor.add(const Duration(days: 1));
  }
  return keys;
}

/// Filter continuous vitals HR samples into `[beginUnix, endUnix]`.
///
/// Never invents samples; empty input or inverted range → empty list.
List<DailyHrSample> windowSleepHrSamples({
  required List<DailyHrSample> samples,
  required int beginUnix,
  required int endUnix,
}) {
  if (beginUnix <= 0 || endUnix <= beginUnix || samples.isEmpty) {
    return const [];
  }
  return samples
      .where(
        (s) =>
            s.bpm > 0 &&
            s.timestampUnix >= beginUnix &&
            s.timestampUnix <= endUnix,
      )
      .toList()
    ..sort((a, b) => a.timestampUnix.compareTo(b.timestampUnix));
}

/// Min / avg / max over a windowed sample list. Null when empty.
({int minBpm, int avgBpm, int maxBpm})? sleepHrStats(
  List<DailyHrSample> samples,
) {
  if (samples.isEmpty) return null;
  var minBpm = samples.first.bpm;
  var maxBpm = samples.first.bpm;
  var sum = 0;
  for (final s in samples) {
    if (s.bpm < minBpm) minBpm = s.bpm;
    if (s.bpm > maxBpm) maxBpm = s.bpm;
    sum += s.bpm;
  }
  return (
    minBpm: minBpm,
    avgBpm: (sum / samples.length).round(),
    maxBpm: maxBpm,
  );
}

String _dayKey(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
