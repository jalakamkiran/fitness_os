import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/trusleep_sleep_sot.dart';

void main() {
  // Aug 11 owner night fragments (IST wall times from handoff; raw capture off-repo).
  const i1 = SleepStateInterval(
    beginUnix: 1_754_860_740,
    endUnix: 1_754_872_020,
  ); // 03:59→07:07
  const i2 = SleepStateInterval(
    beginUnix: 1_754_872_140,
    endUnix: 1_754_876_520,
  ); // 07:09→08:22 (120s gap)
  const i3 = SleepStateInterval(
    beginUnix: 1_754_876_580,
    endUnix: 1_754_877_600,
  ); // 08:23→08:40 (60s gap)

  group('gapMergeChains', () {
    test('Aug 11 fragments with ≤3m gaps → one 281m chain 03:59→08:40', () {
      final chains = TruSleepSleepSot.gapMergeChains(const [i1, i2, i3]);
      expect(chains, hasLength(1));
      expect(chains.single.beginUnix, i1.beginUnix);
      expect(chains.single.endUnix, i3.endUnix);
      expect(
        ((chains.single.endUnix - chains.single.beginUnix) / 60).round(),
        281,
      );
    });

    test('4m gap between fragments → two sessions', () {
      const late = SleepStateInterval(
        beginUnix: 1_754_872_020 + 240, // 4m after i1 end
        endUnix: 1_754_876_520,
      );
      final chains = TruSleepSleepSot.gapMergeChains(const [i1, late]);
      expect(chains, hasLength(2));
      expect(chains[0].beginUnix, i1.beginUnix);
      expect(chains[0].endUnix, i1.endUnix);
      expect(chains[1].beginUnix, late.beginUnix);
      expect(chains[1].endUnix, late.endUnix);
    });

    test('empty intervals → empty list', () {
      expect(TruSleepSleepSot.gapMergeChains(const []), isEmpty);
    });

    test('single nap-length interval → one chain', () {
      const nap = SleepStateInterval(beginUnix: 1000, endUnix: 2800); // 30m
      final chains = TruSleepSleepSot.gapMergeChains(const [nap]);
      expect(chains, hasLength(1));
      expect(chains.single.beginUnix, 1000);
      expect(chains.single.endUnix, 2800);
    });
  });

  group('buildSessions', () {
    test('builds one display session per chain without inventing stages', () {
      final sessions = TruSleepSleepSot.buildSessions(const [i1, i2, i3]);
      expect(sessions, hasLength(1));
      expect(sessions.single.beginUnix, i1.beginUnix);
      expect(sessions.single.endUnix, i3.endUnix);
      expect(sessions.single.stages, isEmpty);
      expect(sessions.single.wireType, isNull);
    });

    test('unsorted input is sorted before merge', () {
      final sessions = TruSleepSleepSot.buildSessions(const [i3, i1, i2]);
      expect(sessions, hasLength(1));
      expect(sessions.single.beginUnix, i1.beginUnix);
      expect(sessions.single.endUnix, i3.endUnix);
    });

    test('Oct 8-shaped three fragments with 9–18m gaps → one overnight', () {
      // Local wall times → unix via DateTime (device TZ).
      int u(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
      final f1 = SleepStateInterval(
        beginUnix: u(DateTime(2026, 10, 8, 0, 30)),
        endUnix: u(DateTime(2026, 10, 8, 3, 10)),
      );
      final f2 = SleepStateInterval(
        beginUnix: u(DateTime(2026, 10, 8, 3, 19)),
        endUnix: u(DateTime(2026, 10, 8, 4, 40)),
      );
      final f3 = SleepStateInterval(
        beginUnix: u(DateTime(2026, 10, 8, 4, 58)),
        endUnix: u(DateTime(2026, 10, 8, 7, 5)),
      );
      // Micro-merge alone would keep three chains (gaps > 3m); nocturnal coalesce joins.
      expect(TruSleepSleepSot.gapMergeChains([f1, f2, f3]), hasLength(3));
      final sessions = TruSleepSleepSot.buildSessions([f1, f2, f3]);
      expect(sessions, hasLength(1));
      expect(sessions.single.beginUnix, f1.beginUnix);
      expect(sessions.single.endUnix, f3.endUnix);
    });
  });

  group('pickHeroSession', () {
    test('prefers recent overnight over older longer fragment', () {
      const olderLong = SleepSessionSummary(
        beginUnix: 1_754_700_000,
        endUnix: 1_754_700_000 + 8 * 3600, // 8h
      );
      final recentShorter = SleepSessionSummary(
        beginUnix: i1.beginUnix,
        endUnix: i3.endUnix, // ~4.7h
      );
      final now = i3.endUnix + 3600;
      final hero = TruSleepSleepSot.pickHeroSession(
        [olderLong, recentShorter],
        nowUnix: now,
      );
      expect(hero?.beginUnix, recentShorter.beginUnix);
      expect(hero?.endUnix, recentShorter.endUnix);
    });

    test('empty sessions → null', () {
      expect(
        TruSleepSleepSot.pickHeroSession(const [], nowUnix: 1),
        isNull,
      );
    });
  });
}
