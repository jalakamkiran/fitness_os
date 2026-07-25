import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:fitness_os/app/splash/fathom_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('splash pumps first frame without hanging', (tester) async {
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: FathomSplash(
          onComplete: () => completed = true,
        ),
      ),
    );

    // First frame must land immediately (no pumpAndSettle — animation runs).
    await tester.pump();
    expect(find.byType(FathomSplash), findsOneWidget);
    expect(find.bySemanticsLabel('Fathom'), findsOneWidget);
    expect(completed, isFalse);

    // Advance past compressed timeline (~1.5s) without hanging the test.
    await tester.pump(const Duration(milliseconds: 1800));
    expect(completed, isTrue);
  });

  testWidgets('skipAnimation completes on next frame', (tester) async {
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: FathomSplash(
          skipAnimation: true,
          onComplete: () => completed = true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(completed, isTrue);
    expect(find.byType(FathomSplash), findsOneWidget);
  });

  test('total duration stays within 2s cold-start budget', () {
    final splash = FathomSplash(onComplete: _noop);
    expect(splash.totalMs, lessThanOrEqualTo(2000));
    expect(splash.totalMs, greaterThan(0));
  });

  testWidgets('dark splash paints without hanging', (tester) async {
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.dark(),
        home: FathomSplash(
          skipAnimation: true,
          onComplete: () => completed = true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(completed, isTrue);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
