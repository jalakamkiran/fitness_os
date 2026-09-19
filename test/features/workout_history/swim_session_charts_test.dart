import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';

void main() {
  testWidgets('hides when no interval laps', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SwimSessionCharts(laps: [])),
      ),
    );
    expect(find.text('Session charts'), findsNothing);
  });

  testWidgets('hides when laps have no chartable series', (tester) async {
    const laps = [
      SwimLapMetrics(index: 0, distanceM: 25),
      SwimLapMetrics(index: 1, distanceM: 25),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SwimSessionCharts(laps: laps)),
      ),
    );
    expect(find.text('Session charts'), findsNothing);
  });

  testWidgets('shows Pace → SWOLF → Strokes → Overlay in locked order',
      (tester) async {
    const laps = [
      SwimLapMetrics(
        index: 0,
        distanceM: 25,
        durationSec: 40,
        strokes: 18,
        swolf: 58,
        paceSecPer100m: 160,
      ),
      SwimLapMetrics(
        index: 1,
        distanceM: 25,
        durationSec: 42,
        strokes: 19,
        swolf: 61,
        paceSecPer100m: 168,
      ),
      SwimLapMetrics(
        index: 2,
        distanceM: 25,
        durationSec: 41,
        strokes: 18,
        swolf: 59,
        paceSecPer100m: 164,
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SwimSessionCharts(laps: laps),
          ),
        ),
      ),
    );

    expect(find.text('Session charts'), findsOneWidget);
    expect(find.textContaining('synced to table'), findsOneWidget);

    expect(find.text('Pace by interval'), findsOneWidget);
    expect(find.text('SWOLF'), findsOneWidget);
    expect(find.text('Strokes per length'), findsOneWidget);
    expect(find.text('Pace + SWOLF'), findsOneWidget);

    expect(find.text('s/100m · higher = slower'), findsOneWidget);
    expect(find.text('time + strokes · lower better'), findsOneWidget);
    expect(find.text('count · spike = churn'), findsOneWidget);
    expect(find.text('0–1 normalized · ↑ = worse'), findsOneWidget);

    // Overlay legend present when both series exist.
    expect(find.textContaining('pace'), findsOneWidget);
    expect(find.text('swolf'), findsOneWidget);

    // Title order: Pace before SWOLF before Strokes before Overlay.
    final paceY = tester.getTopLeft(find.text('Pace by interval')).dy;
    final swolfY = tester.getTopLeft(find.text('SWOLF')).dy;
    final strokesY = tester.getTopLeft(find.text('Strokes per length')).dy;
    final overlayY = tester.getTopLeft(find.text('Pace + SWOLF')).dy;
    expect(paceY, lessThan(swolfY));
    expect(swolfY, lessThan(strokesY));
    expect(strokesY, lessThan(overlayY));
  });

  testWidgets('omits overlay when SWOLF missing', (tester) async {
    const laps = [
      SwimLapMetrics(
        index: 0,
        distanceM: 25,
        durationSec: 40,
        strokes: 18,
        paceSecPer100m: 160,
      ),
      SwimLapMetrics(
        index: 1,
        distanceM: 25,
        durationSec: 42,
        strokes: 19,
        paceSecPer100m: 168,
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SwimSessionCharts(laps: laps),
          ),
        ),
      ),
    );

    expect(find.text('Pace by interval'), findsOneWidget);
    expect(find.text('Strokes per length'), findsOneWidget);
    expect(find.text('Pace + SWOLF'), findsNothing);
    expect(find.text('SWOLF'), findsNothing);
  });

  testWidgets('does not show a silent-omit stand-in for missing HR samples',
      (tester) async {
    const laps = [
      SwimLapMetrics(
        index: 0,
        distanceM: 25,
        durationSec: 40,
        strokes: 18,
        swolf: 58,
        paceSecPer100m: 160,
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SwimSessionCharts(laps: laps),
          ),
        ),
      ),
    );

    expect(find.textContaining('Heart rate — hidden'), findsNothing);
    expect(find.textContaining('HR absent'), findsNothing);
  });
}
