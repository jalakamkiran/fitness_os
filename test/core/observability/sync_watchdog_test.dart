import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry/sentry.dart';

import 'package:fitness_os/core/observability/sentry_sync_instrumentation.dart';

void main() {
  group('timeoutForWindow / windowClass', () {
    test('short window → incremental + 4 min budget', () {
      const start = 1_700_000_000;
      const end = start + 14 * 24 * 60 * 60;
      expect(
        SentrySyncInstrumentation.windowClass(
          startUnix: start,
          endUnix: end,
        ),
        'incremental',
      );
      expect(
        SentrySyncInstrumentation.timeoutForWindow(
          startUnix: start,
          endUnix: end,
        ),
        const Duration(minutes: 4),
      );
    });

    test('60d+ window → full_history + 20 min budget', () {
      const start = 1_700_000_000;
      const end = start + 60 * 24 * 60 * 60;
      expect(
        SentrySyncInstrumentation.windowClass(
          startUnix: start,
          endUnix: end,
        ),
        'full_history',
      );
      expect(
        SentrySyncInstrumentation.timeoutForWindow(
          startUnix: start,
          endUnix: end,
        ),
        const Duration(minutes: 20),
      );
    });
  });

  group('invokeWithTimeout', () {
    test('completes before threshold → returns value', () async {
      final value = await SentrySyncInstrumentation.invokeWithTimeout(
        future: Future.value(42),
        timeout: const Duration(seconds: 1),
        channel: 'syncWorkouts',
        onAbandoned: () => -1,
      );
      expect(value, 42);
    });

    test('exceeds threshold → onAbandoned, no throw', () async {
      final completer = Completer<int>();
      final value = await SentrySyncInstrumentation.invokeWithTimeout(
        future: completer.future,
        timeout: const Duration(milliseconds: 20),
        channel: 'syncWorkouts',
        onAbandoned: () => 7,
      );
      expect(value, 7);
      // Late completion must not be used by caller (simulates superseded).
      completer.complete(99);
    });
  });

  group('finishWithStatus mapping', () {
    test('stuck / abandoned map to deadlineExceeded', () {
      expect(
        SentrySyncInstrumentation.mapStatusForTest('stuck'),
        const SpanStatus.deadlineExceeded(),
      );
      expect(
        SentrySyncInstrumentation.mapStatusForTest('abandoned'),
        const SpanStatus.deadlineExceeded(),
      );
      expect(
        SentrySyncInstrumentation.mapStatusForTest('ok'),
        const SpanStatus.ok(),
      );
    });
  });
}
