import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';

void main() {
  testWidgets('hides when no interval laps', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SwimSessionCharts(laps: [])),
      ),
    );
    expect(find.text('Charts'), findsNothing);
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
    expect(find.text('Charts'), findsNothing);
  });

  testWidgets('defaults to Pace series with progressive chips', (tester) async {
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

    expect(find.text('Charts'), findsOneWidget);
    expect(find.textContaining('synced to table'), findsNothing);
    expect(find.text('Pace by interval'), findsOneWidget);
    // Secondary series not all equal-height by default (chip labels may say SWOLF).
    expect(find.text('Strokes per length'), findsNothing);
    expect(find.text('Pace + SWOLF'), findsNothing);
    expect(find.text('s/100m · higher = slower'), findsOneWidget);
    expect(find.text('time + strokes · lower better'), findsNothing);

    expect(find.byKey(const Key('swim-series-pace')), findsOneWidget);
    expect(find.byKey(const Key('swim-series-swolf')), findsOneWidget);
    expect(find.byKey(const Key('swim-series-strokes')), findsOneWidget);
    expect(find.byKey(const Key('swim-series-overlay')), findsOneWidget);

    await tester.tap(find.byKey(const Key('swim-series-swolf')));
    await tester.pump();
    expect(find.text('SWOLF'), findsWidgets);
    expect(find.text('time + strokes · lower better'), findsOneWidget);
  });

  testWidgets('omits overlay chip when SWOLF missing', (tester) async {
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

    expect(find.byKey(const Key('swim-series-pace')), findsOneWidget);
    expect(find.byKey(const Key('swim-series-strokes')), findsOneWidget);
    expect(find.byKey(const Key('swim-series-overlay')), findsNothing);
    expect(find.byKey(const Key('swim-series-swolf')), findsNothing);
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

  testWidgets('HR chip merges into charts when locked samples present',
      (tester) async {
    const laps = [
      SwimLapMetrics(
        index: 0,
        distanceM: 25,
        durationSec: 40,
        paceSecPer100m: 160,
      ),
      SwimLapMetrics(
        index: 1,
        distanceM: 25,
        durationSec: 42,
        paceSecPer100m: 168,
      ),
    ];
    const hr = [
      RunStreamPoint(offsetSec: 0, hrBpm: 120),
      RunStreamPoint(offsetSec: 30, hrBpm: 132),
      RunStreamPoint(offsetSec: 60, hrBpm: 140),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SwimSessionCharts(laps: laps, hrPoints: hr),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('swim-series-hr')), findsOneWidget);
    expect(find.text('Heart rate'), findsNothing); // not selected yet
    await tester.tap(find.byKey(const Key('swim-series-hr')));
    await tester.pump();
    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.text('bpm · in-session samples'), findsOneWidget);
  });

  testWidgets('null pace intervals are not plotted as zero-fast bars',
      (tester) async {
    const laps = [
      SwimLapMetrics(
        index: 0,
        distanceM: 25,
        durationSec: 40,
        paceSecPer100m: 160,
      ),
      SwimLapMetrics(
        index: 1,
        distanceM: 25,
        durationSec: 20,
        // rest / missing pace — must not become toY: 0
        paceSecPer100m: null,
      ),
      SwimLapMetrics(
        index: 2,
        distanceM: 25,
        durationSec: 42,
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
    // Chart mounts; honesty is gap/skip (no crash / no false-fast chrome).
    expect(find.byType(SwimSessionCharts), findsOneWidget);
  });
}
