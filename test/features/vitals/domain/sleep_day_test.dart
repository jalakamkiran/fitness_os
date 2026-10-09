import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/sleep_day.dart';

void main() {
  SleepSessionSummary session(DateTime begin, DateTime end) =>
      SleepSessionSummary(
        beginUnix: begin.millisecondsSinceEpoch ~/ 1000,
        endUnix: end.millisecondsSinceEpoch ~/ 1000,
      );

  group('SleepDay.coalesceNocturnalSessions', () {
    test('merges mid-night wake gap under 90m into one overnight', () {
      final a = session(
        DateTime(2026, 9, 14, 23, 0),
        DateTime(2026, 9, 15, 2, 0),
      );
      final b = session(
        DateTime(2026, 9, 15, 2, 20),
        DateTime(2026, 9, 15, 6, 30),
      );
      final out = SleepDay.coalesceNocturnalSessions([a, b]);
      expect(out, hasLength(1));
      expect(out.single.beginUnix, a.beginUnix);
      expect(out.single.endUnix, b.endUnix);
      expect(out.single.durationSec, closeTo(7.5 * 3600, 1));
    });

    test('Oct 8-shaped 9m mid-night gap → one overnight', () {
      final a = session(
        DateTime(2026, 10, 8, 0, 30),
        DateTime(2026, 10, 8, 3, 10),
      );
      final b = session(
        DateTime(2026, 10, 8, 3, 19),
        DateTime(2026, 10, 8, 7, 0),
      );
      final out = SleepDay.coalesceNocturnalSessions([a, b]);
      expect(out, hasLength(1));
      expect(out.single.beginUnix, a.beginUnix);
      expect(out.single.endUnix, b.endUnix);
      expect(SleepDay.kindLabel(out.single), 'overnight');
    });

    test('Oct 9-shaped 18m mid-night gap → one overnight', () {
      final a = session(
        DateTime(2026, 10, 9, 0, 45),
        DateTime(2026, 10, 9, 3, 0),
      );
      final b = session(
        DateTime(2026, 10, 9, 3, 18),
        DateTime(2026, 10, 9, 4, 30),
      );
      final c = session(
        DateTime(2026, 10, 9, 4, 48),
        DateTime(2026, 10, 9, 7, 15),
      );
      final out = SleepDay.coalesceNocturnalSessions([a, b, c]);
      expect(out, hasLength(1));
      expect(out.single.beginUnix, a.beginUnix);
      expect(out.single.endUnix, c.endUnix);
    });

    test('100m nocturnal gap without SEQUENCE → remain split', () {
      final a = session(
        DateTime(2026, 10, 8, 0, 30),
        DateTime(2026, 10, 8, 3, 0),
      );
      final b = session(
        DateTime(2026, 10, 8, 4, 41),
        DateTime(2026, 10, 8, 7, 0),
      );
      final out = SleepDay.coalesceNocturnalSessions([a, b]);
      expect(out, hasLength(2));
    });

    test('does not merge afternoon nap onto morning', () {
      final night = session(
        DateTime(2026, 9, 14, 23, 0),
        DateTime(2026, 9, 15, 7, 0),
      );
      final nap = session(
        DateTime(2026, 9, 15, 14, 0),
        DateTime(2026, 9, 15, 15, 30),
      );
      final out = SleepDay.coalesceNocturnalSessions([night, nap]);
      expect(out, hasLength(2));
      expect(SleepDay.kindLabel(out[0]), 'overnight');
      expect(SleepDay.kindLabel(out[1]), 'nap');
    });

    test('does not glue lunch nap onto late morning sleep', () {
      final morning = session(
        DateTime(2026, 9, 15, 8, 0),
        DateTime(2026, 9, 15, 11, 0),
      );
      final nap = session(
        DateTime(2026, 9, 15, 12, 0),
        DateTime(2026, 9, 15, 13, 0),
      );
      final out = SleepDay.coalesceNocturnalSessions([morning, nap]);
      expect(out, hasLength(2));
    });

    test('overnight ending before 10:00 does not glue ≤90m later nap', () {
      final night = session(
        DateTime(2026, 10, 8, 23, 0),
        DateTime(2026, 10, 9, 9, 30),
      );
      final nap = session(
        DateTime(2026, 10, 9, 10, 45),
        DateTime(2026, 10, 9, 12, 0),
      );
      final out = SleepDay.coalesceNocturnalSessions([night, nap]);
      expect(out, hasLength(2));
    });

    test('SEQUENCE main + 20m post-wakeup orphan stay separate', () {
      final main = session(
        DateTime(2026, 10, 9, 0, 30),
        DateTime(2026, 10, 9, 7, 0),
      );
      final orphan = session(
        DateTime(2026, 10, 9, 7, 20),
        DateTime(2026, 10, 9, 7, 50),
      );
      final out = SleepDay.coalesceNocturnalSessions([main, orphan]);
      expect(out, hasLength(2));
      expect(out[0].endUnix, main.endUnix);
      expect(out[1].beginUnix, orphan.beginUnix);
    });
  });

  group('SleepDay.resolve', () {
    test('overnight + afternoon nap → primary overnight, nap listed', () {
      final night = session(
        DateTime(2026, 8, 12, 23, 0),
        DateTime(2026, 8, 13, 7, 0),
      );
      final nap = session(
        DateTime(2026, 8, 13, 14, 0),
        DateTime(2026, 8, 13, 16, 0),
      );
      final day = SleepDay.resolve(
        [night, nap],
        now: DateTime(2026, 8, 13, 17),
      );
      expect(day.totalDurationSec, night.durationSec + nap.durationSec);
      expect(day.primary?.beginUnix, night.beginUnix);
      expect(day.napSessions, hasLength(1));
    });

    test('fragmented night shows one primary overnight', () {
      final a = session(
        DateTime(2026, 9, 14, 23, 30),
        DateTime(2026, 9, 15, 2, 30),
      );
      final b = session(
        DateTime(2026, 9, 15, 2, 45),
        DateTime(2026, 9, 15, 6, 0),
      );
      final day = SleepDay.resolve(
        [a, b],
        now: DateTime(2026, 9, 15, 11),
      );
      expect(day.members, hasLength(1));
      expect(day.primary, isNotNull);
      expect(SleepDay.isIntentionalNap(day.primary!), isFalse);
      expect(day.napSessions, isEmpty);
      expect(day.totalDurationSec, day.primary!.durationSec);
    });

    test('evening onset after 20:00 belongs to next sleep-day', () {
      final evening = session(
        DateTime(2026, 8, 13, 21, 0),
        DateTime(2026, 8, 14, 6, 0),
      );
      final afternoon = SleepDay.resolve(
        [evening],
        now: DateTime(2026, 8, 13, 17),
      );
      expect(afternoon.isEmpty, isTrue);

      final eveningView = SleepDay.resolve(
        [evening],
        now: DateTime(2026, 8, 13, 22),
      );
      expect(eveningView.primary?.beginUnix, evening.beginUnix);

      final nextMorning = SleepDay.resolve(
        [evening],
        now: DateTime(2026, 8, 14, 10),
      );
      expect(nextMorning.primary?.beginUnix, evening.beginUnix);
    });

    test('scientific short night ranks as primary overnight', () {
      final shortScientific = session(
        DateTime(2026, 10, 9, 6, 0),
        DateTime(2026, 10, 9, 8, 30),
      );
      final nap = session(
        DateTime(2026, 10, 9, 14, 0),
        DateTime(2026, 10, 9, 15, 0),
      );
      expect(SleepDay.isIntentionalNap(shortScientific), isTrue);
      expect(
        SleepDay.isIntentionalNap(shortScientific, scientificMain: true),
        isFalse,
      );
      expect(
        SleepDay.kindLabel(shortScientific, scientificMain: true),
        'overnight',
      );

      final day = SleepDay.resolve(
        [shortScientific, nap],
        now: DateTime(2026, 10, 9, 17),
        scientificMainKeys: {shortScientific.mergeKey},
      );
      expect(day.primary?.mergeKey, shortScientific.mergeKey);
      expect(day.napSessions, hasLength(1));
    });
  });

  group('SleepDay.isIntentionalNap', () {
    test('afternoon short session is a nap', () {
      final nap = session(
        DateTime(2026, 9, 15, 14, 0),
        DateTime(2026, 9, 15, 15, 0),
      );
      expect(SleepDay.isIntentionalNap(nap), isTrue);
      expect(SleepDay.kindLabel(nap), 'nap');
    });

    test('same-calendar-day early-morning overnight is not a nap', () {
      final night = session(
        DateTime(2026, 10, 7, 1, 36),
        DateTime(2026, 10, 7, 8, 11),
      );
      expect(SleepDay.isIntentionalNap(night), isFalse);
      expect(SleepDay.kindLabel(night), 'overnight');
    });

    test('midnight-crossing short fragment is not a nap', () {
      final frag = session(
        DateTime(2026, 9, 14, 23, 0),
        DateTime(2026, 9, 15, 1, 30),
      );
      expect(SleepDay.isIntentionalNap(frag), isFalse);
      expect(SleepDay.kindLabel(frag), 'overnight');
    });

    test('≥3h daytime sleep is not labeled nap', () {
      final long = session(
        DateTime(2026, 9, 15, 10, 0),
        DateTime(2026, 9, 15, 14, 0),
      );
      expect(SleepDay.isIntentionalNap(long), isFalse);
    });
  });
}
