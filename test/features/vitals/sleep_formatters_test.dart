import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/sleep_formatters.dart';

void main() {
  test('todaysSleepSession prefers overnight over same-day nap', () {
    final now = DateTime(2024, 6, 2, 18);
    final overnightBegin =
        DateTime(2024, 6, 1, 23).millisecondsSinceEpoch ~/ 1000;
    final overnightEnd =
        DateTime(2024, 6, 2, 6).millisecondsSinceEpoch ~/ 1000;
    final napBegin =
        DateTime(2024, 6, 2, 13).millisecondsSinceEpoch ~/ 1000;
    final napEnd =
        DateTime(2024, 6, 2, 14, 30).millisecondsSinceEpoch ~/ 1000;
    // beginUnix-desc order (as prefs load returns)
    final sessions = [
      SleepSessionSummary(beginUnix: napBegin, endUnix: napEnd),
      SleepSessionSummary(beginUnix: overnightBegin, endUnix: overnightEnd),
    ];
    final today = todaysSleepSession(sessions, now: now);
    expect(today, isNotNull);
    expect(today!.beginUnix, overnightBegin);
    expect(sleepIsMainOvernight(today), isTrue);
    expect(sleepSessionKindLabel(today), 'overnight');
  });

  test('todaysSleepSession picks longest when no overnight', () {
    final now = DateTime(2024, 6, 2, 18);
    final shortBegin =
        DateTime(2024, 6, 2, 12).millisecondsSinceEpoch ~/ 1000;
    final shortEnd =
        DateTime(2024, 6, 2, 12, 40).millisecondsSinceEpoch ~/ 1000;
    final longBegin =
        DateTime(2024, 6, 2, 14).millisecondsSinceEpoch ~/ 1000;
    final longEnd =
        DateTime(2024, 6, 2, 16).millisecondsSinceEpoch ~/ 1000;
    final today = todaysSleepSession(
      [
        SleepSessionSummary(beginUnix: shortBegin, endUnix: shortEnd),
        SleepSessionSummary(beginUnix: longBegin, endUnix: longEnd),
      ],
      now: now,
    );
    expect(today!.beginUnix, longBegin);
  });

  test('Oct 7-shaped same-calendar-day night is overnight, not nap', () {
    final night = SleepSessionSummary(
      beginUnix:
          DateTime(2026, 10, 7, 1, 36).millisecondsSinceEpoch ~/ 1000,
      endUnix: DateTime(2026, 10, 7, 8, 11).millisecondsSinceEpoch ~/ 1000,
    );
    expect(sleepCrossesLocalMidnight(night), isFalse);
    expect(sleepIsMainOvernight(night), isTrue);
    expect(sleepSessionKindLabel(night), 'overnight');
    expect(sleepIsIntentionalNap(night), isFalse);

    final today = todaysSleepSession(
      [night],
      now: DateTime(2026, 10, 7, 17),
    );
    expect(today?.beginUnix, night.beginUnix);
  });

  test('afternoon nap does not replace overnight primary', () {
    final night = SleepSessionSummary(
      beginUnix:
          DateTime(2026, 10, 9, 0, 45).millisecondsSinceEpoch ~/ 1000,
      endUnix: DateTime(2026, 10, 9, 7, 15).millisecondsSinceEpoch ~/ 1000,
    );
    final nap = SleepSessionSummary(
      beginUnix:
          DateTime(2026, 10, 9, 14, 0).millisecondsSinceEpoch ~/ 1000,
      endUnix: DateTime(2026, 10, 9, 15, 0).millisecondsSinceEpoch ~/ 1000,
    );
    final today = todaysSleepSession(
      [nap, night],
      now: DateTime(2026, 10, 9, 17),
    );
    expect(today?.beginUnix, night.beginUnix);
    expect(sleepSessionKindLabel(nap), 'nap');
  });
}
