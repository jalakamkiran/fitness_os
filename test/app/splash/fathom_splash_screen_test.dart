import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:fitness_os/app/splash/fathom_splash_screen.dart';
import 'package:fitness_os/app/splash/fathom_splash_timing.dart';
import 'package:fitness_os/app/splash/fathom_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('splash pumps without hanging and notifies on finish',
      (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: FathomSplashScreen(
          timing: FathomSplashTiming.instant,
          onFinished: () => finished++,
        ),
      ),
    );

    // First frame paints the splash; instant timing finishes post-frame.
    await tester.pump();
    expect(find.byType(FathomSplashScreen), findsOneWidget);
    expect(find.byType(FathomWordmark), findsOneWidget);
    expect(find.bySemanticsLabel('Fathom'), findsOneWidget);

    await tester.pump(); // post-frame callback
    expect(finished, 1);

    // No pending timers / animations left that would hang pumpAndSettle.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(finished, 1);
  });

  testWidgets('standard timing completes within 2s budget', (tester) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: FathomSplashScreen(
          timing: FathomSplashTiming.standard,
          onFinished: () => finished = true,
        ),
      ),
    );

    await tester.pump();
    expect(finished, isFalse);

    // Advance past the capped brand moment (~1.55s) with headroom.
    await tester.pump(const Duration(milliseconds: 1800));
    expect(finished, isTrue);
    expect(
      FathomSplashTiming.standard.total.inMilliseconds,
      lessThanOrEqualTo(2000),
    );
  });

  testWidgets('splash gate dismisses and reveals child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: FathomSplashGate(
          timing: FathomSplashTiming.instant,
          child: const Text('shell-ready'),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('shell-ready'), findsOneWidget);
    expect(find.byType(FathomSplashScreen), findsOneWidget);

    await tester.pump(); // finish
    await tester.pumpAndSettle();
    expect(find.text('shell-ready'), findsOneWidget);
    expect(find.byType(FathomSplashScreen), findsNothing);
  });

  test('standard timing stays within product hold budget', () {
    expect(
      FathomSplashTiming.standard.total,
      lessThanOrEqualTo(const Duration(seconds: 2)),
    );
    expect(
      FathomSplashTiming.standard.total,
      greaterThan(Duration.zero),
    );
  });
}
