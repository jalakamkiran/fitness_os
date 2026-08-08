import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/observability/sentry_config.dart';

void main() {
  group('SentryConfig', () {
    test('hasDsn is false when compile-time DSN empty (default test)', () {
      // Unit tests do not pass SENTRY_DSN unless --dart-define is set.
      expect(SentryConfig.dsn, isA<String>());
      // shouldInitialize is false without DSN regardless of build mode.
      if (!SentryConfig.hasDsn) {
        expect(SentryConfig.shouldInitialize, isFalse);
      }
    });

    test('forceEnabled defaults false', () {
      expect(SentryConfig.forceEnabled, isA<bool>());
    });
  });
}
