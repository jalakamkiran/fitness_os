import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OneShotAutoSync', () {
    test('fires once per resume when session is ready', () async {
      var passCalls = 0;
      final sync = OneShotAutoSync(
        isSessionReady: () => true,
        isSyncBusy: () => false,
        runPass: () async {
          passCalls++;
        },
      );

      sync.onResumed();
      await Future<void>.delayed(Duration.zero);
      expect(sync.passStarts, 1);
      expect(passCalls, 1);

      // Same resume window — session-ready must not start a second pass.
      sync.onSessionReady();
      final second = await sync.trySchedule();
      expect(second, AutoSyncOutcome.alreadyFired);
      expect(sync.passStarts, 1);
      expect(passCalls, 1);

      // Background then resume arms a fresh one-shot.
      sync.onBackgrounded();
      sync.onResumed();
      await Future<void>.delayed(Duration.zero);
      expect(sync.passStarts, 2);
      expect(passCalls, 2);
    });

    test('cold-open resume + lifecycle resumed still fires once', () async {
      var passCalls = 0;
      final sync = OneShotAutoSync(
        isSessionReady: () => true,
        isSyncBusy: () => false,
        runPass: () async {
          passCalls++;
        },
      );

      sync.onResumed(); // cold open
      sync.handleLifecycle(AppLifecycleState.resumed); // duplicate signal
      await Future<void>.delayed(Duration.zero);

      expect(sync.passStarts, 1);
      expect(passCalls, 1);
    });

    test('rejects when shared sync lock is busy', () async {
      var passCalls = 0;
      var busy = true;
      final sync = OneShotAutoSync(
        isSessionReady: () => true,
        isSyncBusy: () => busy,
        runPass: () async {
          passCalls++;
        },
      );

      sync.onResumed();
      final outcome = await sync.trySchedule();
      expect(outcome, AutoSyncOutcome.rejectedBusy);
      expect(passCalls, 0);
      expect(sync.passStarts, 0);

      // After lock frees in the same resume, a later schedule may run.
      busy = false;
      final after = await sync.trySchedule();
      expect(after, AutoSyncOutcome.ran);
      expect(passCalls, 1);
    });

    test('concurrent schedule while pass in flight → alreadyFired', () async {
      final gate = Completer<void>();
      final sync = OneShotAutoSync(
        isSessionReady: () => true,
        isSyncBusy: () => false,
        runPass: () => gate.future,
      );

      sync.onResumed();
      await Future<void>.delayed(Duration.zero);
      expect(sync.passInFlight, isTrue);
      expect(sync.passStarts, 1);

      final overlapping = await sync.trySchedule();
      expect(overlapping, AutoSyncOutcome.alreadyFired);
      expect(sync.passStarts, 1);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(sync.passInFlight, isFalse);
    });

    test('notReady until session ready, then one pass', () async {
      var ready = false;
      var passCalls = 0;
      final sync = OneShotAutoSync(
        isSessionReady: () => ready,
        isSyncBusy: () => false,
        runPass: () async {
          passCalls++;
        },
      );

      sync.onResumed();
      await Future<void>.delayed(Duration.zero);
      expect(passCalls, 0);

      ready = true;
      sync.onSessionReady();
      await Future<void>.delayed(Duration.zero);
      expect(passCalls, 1);
      expect(sync.passStarts, 1);
    });

    test('never starts sticky foreground service (R11)', () async {
      var fgsStarts = 0;
      final sync = OneShotAutoSync(
        isSessionReady: () => true,
        isSyncBusy: () => false,
        startForegroundService: () async {
          fgsStarts++;
        },
        runPass: () async {},
      );

      expect(sync.hasForegroundServiceStarter, isTrue);
      sync.onResumed();
      await Future<void>.delayed(Duration.zero);

      expect(sync.passStarts, 1);
      expect(fgsStarts, 0);
      expect(sync.foregroundServiceStarts, 0);
    });

    test('inactive when not foregrounded', () async {
      final sync = OneShotAutoSync(
        isSessionReady: () => true,
        isSyncBusy: () => false,
        runPass: () async {},
      );

      final outcome = await sync.trySchedule();
      expect(outcome, AutoSyncOutcome.inactive);
      expect(sync.passStarts, 0);
    });
  });
}
