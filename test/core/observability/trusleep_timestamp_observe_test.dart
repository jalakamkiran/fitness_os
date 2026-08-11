import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/observability/sentry_privacy_scrub.dart';
import 'package:fitness_os/core/observability/trusleep_timestamp_observe.dart';

void main() {
  group('TruSleepTimestampObserve.mergeNearAdjacent', () {
    test('merges trailing fragments with gap ≤ 3m', () {
      const a = SleepStateInterval(beginUnix: 1000, endUnix: 2000);
      const b = SleepStateInterval(beginUnix: 2100, endUnix: 3000); // 100s gap
      const c = SleepStateInterval(beginUnix: 4000, endUnix: 5000); // big gap
      final merged = TruSleepTimestampObserve.mergeNearAdjacent([a, b, c]);
      expect(merged?.beginUnix, 4000);
      expect(merged?.endUnix, 5000);

      final night = TruSleepTimestampObserve.mergeNearAdjacent([a, b]);
      expect(night?.beginUnix, 1000);
      expect(night?.endUnix, 3000);
    });
  });

  group('TruSleepTimestampObserve.buildPayload', () {
    test('computes delta vs longest recent message session', () {
      // File: 03:59–08:40-ish as three fragments → merged
      const i1 = SleepStateInterval(beginUnix: 1_754_860_740, endUnix: 1_754_872_020);
      const i2 = SleepStateInterval(beginUnix: 1_754_872_140, endUnix: 1_754_876_520);
      const i3 = SleepStateInterval(beginUnix: 1_754_876_580, endUnix: 1_754_877_600);
      const msg = SleepSessionSummary(
        beginUnix: 1_754_858_940, // ~30m earlier
        endUnix: 1_754_875_800,
      );
      final payload = TruSleepTimestampObserve.buildPayload(
        messageSessions: const [msg],
        enrich: [
          SleepEnrichOutcome(
            beginUnix: msg.beginUnix,
            endUnix: msg.endUnix,
            present: true,
            stateIntervals: const [i1, i2, i3],
            refs: const [
              SleepFileRef(id: 'sleep_state', len: 528),
              SleepFileRef(id: 'sleep_data', len: 694564),
            ],
          ),
        ],
        watchClock: const WatchClockSnapshot(
          zoneId: 'Asia/Kolkata',
          offsetSec: 19800,
          offsetLabel: 'UTC+05:30',
          skewSec: 0,
        ),
        nowUnix: msg.endUnix + 3600,
      );

      expect(payload['zone_id'], 'Asia/Kolkata');
      expect(payload['skew_sec'], 0);
      expect(payload['file_interval_count'], 3);
      expect(payload['file_merged_begin'], i1.beginUnix);
      expect(payload['file_merged_end'], i3.endUnix);
      expect(payload['delta_start_min'], 30);
      expect(payload['state_len'], 528);
      expect(payload['data_len'], 694564);
      expect((payload['tails'] as String).contains('${i3.beginUnix}'), isTrue);

      final scrubbed = SentryPrivacyScrub.scrubMap(
        Map<String, dynamic>.from(payload),
      );
      expect(scrubbed?['delta_start_min'], 30);
      expect(scrubbed?['zone_id'], 'Asia/Kolkata');
      expect(scrubbed?['tails'], isNotEmpty);
    });
  });
}
