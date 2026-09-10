import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fitness_os/core/observability/sentry_privacy_scrub.dart';

void main() {
  group('SentryPrivacyScrub.redactText', () {
    test('redacts colon MAC', () {
      final out = SentryPrivacyScrub.redactText(
        'link mac=AA:BB:CC:DD:EE:FF ok',
      );
      expect(out, isNot(contains('AA:BB:CC:DD:EE:FF')));
      expect(out, contains('••:••:••:••:••:••'));
    });

    test('redacts hex dump blobs', () {
      final out = SentryPrivacyScrub.redactText(
        'pkt 01 02 03 04 05 06 07 08 09 0a',
      );
      expect(out, contains('[hex-redacted]'));
    });
  });

  group('SentryPrivacyScrub.scrubMap', () {
    test('keeps safe link status fields', () {
      final out = SentryPrivacyScrub.scrubMap({
        'state': 'connected',
        'elapsed_ms': 1200,
      });
      expect(out, {
        'state': 'connected',
        'elapsed_ms': 1200,
      });
    });

    test('drops forbidden workout/HR keys', () {
      final out = SentryPrivacyScrub.scrubMap({
        'status': 'ok',
        'workouts': [
          {'id': 1, 'mac': 'AABBCCDDEEFF'},
        ],
        'hrSeries': [60, 62],
        'mac': 'AA:BB:CC:DD:EE:FF',
        'gemini_api_key': 'secret',
      });
      expect(out?.containsKey('workouts'), isFalse);
      expect(out?.containsKey('hrSeries'), isFalse);
      expect(out?.containsKey('mac'), isFalse);
      expect(out?.containsKey('gemini_api_key'), isFalse);
      expect(out?['status'], 'ok');
    });

    test('drops leftover / HR points / recovery-HR aliases', () {
      final out = SentryPrivacyScrub.scrubMap({
        'status': 'ok',
        'leftover': 'deadbeef',
        'leftoverBytes': 'aabb',
        'hrPoints': [70, 72],
        'recoveryHr': 'blob',
        'recoveryHeartRates': 'blob2',
        'pointsBytesBase64': 'YQ==',
        'nested': {
          'leftoverBytesHex': 'ff00',
          'safe': true,
        },
      });
      expect(out?.containsKey('leftover'), isFalse);
      expect(out?.containsKey('leftoverBytes'), isFalse);
      expect(out?.containsKey('hrPoints'), isFalse);
      expect(out?.containsKey('recoveryHr'), isFalse);
      expect(out?.containsKey('recoveryHeartRates'), isFalse);
      expect(out?.containsKey('pointsBytesBase64'), isFalse);
      expect(out?['nested']?.containsKey('leftoverBytesHex'), isFalse);
      expect(out?['nested']?['safe'], isTrue);
      expect(out?['status'], 'ok');
    });

    test('drops PlatformException-shaped details', () {
      final out = SentryPrivacyScrub.scrubMap({
        'code': 'sync_failed',
        'details': {
          'workouts': [
            {'segments': []},
          ],
        },
        'arguments': {'startUnix': 1},
        'result': {'sleepSessions': []},
      });
      expect(out?.containsKey('details'), isFalse);
      expect(out?.containsKey('arguments'), isFalse);
      expect(out?.containsKey('result'), isFalse);
      expect(out?['code'], 'sync_failed');
    });
  });

  group('beforeSend hooks', () {
    test('beforeSend redacts MAC in message and strips forbidden extras', () {
      final event = SentryEvent(
        message: SentryMessage('paired AA:BB:CC:DD:EE:FF'),
        extra: {
          'status': 'ok',
          'workouts': [
            {'id': 1},
          ],
        },
      );
      final out = SentryPrivacyScrub.beforeSend(event, Hint());
      expect(out?.message?.formatted, isNot(contains('AA:BB:CC:DD:EE:FF')));
      expect(out?.extra?.containsKey('workouts'), isFalse);
      expect(out?.extra?['status'], 'ok');
    });

    test('beforeSendTransaction uses scrubMap on data', () {
      // Exercise the same scrub path beforeSendTransaction applies to txn.data.
      final scrubbed = SentryPrivacyScrub.scrubMap({
        'status': 'stuck',
        'workouts': [
          {'id': 9},
        ],
      });
      expect(scrubbed?.containsKey('workouts'), isFalse);
      expect(scrubbed?['status'], 'stuck');
    });

    test('beforeBreadcrumb redacts message MAC', () {
      final crumb = Breadcrumb(
        message: 'connect AA:BB:CC:DD:EE:FF',
        data: {'mac': 'AABBCCDDEEFF', 'state': 'connected'},
      );
      final out = SentryPrivacyScrub.beforeBreadcrumb(crumb, Hint());
      expect(out?.message, isNot(contains('AA:BB:CC:DD:EE:FF')));
      expect(out?.data?.containsKey('mac'), isFalse);
      expect(out?.data?['state'], 'connected');
    });
  });
}
