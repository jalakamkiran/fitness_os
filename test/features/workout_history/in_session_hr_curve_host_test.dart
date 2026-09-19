import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/in_session_hr_curve_host.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/strength_session_analytics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const locked = [
    RunStreamPoint(offsetSec: 0, hrBpm: 120, cadenceSpm: 90),
    RunStreamPoint(offsetSec: 5, hrBpm: 128, cadenceSpm: 92),
    RunStreamPoint(offsetSec: 10, hrBpm: 131, cadenceSpm: 88),
  ];

  WorkoutSummary swim({
    int type = 6,
    int? sampleCount,
    List<WorkoutSegment>? segments,
  }) {
    return WorkoutSummary(
      number: 67,
      startTime: 1723000000,
      endTime: 1723001800,
      durationSec: 1800,
      type: type,
      hrMin: 76,
      hrMax: 153,
      sampleCount: sampleCount,
      poolLength: 2500,
      segments: segments,
    );
  }

  WorkoutSummary strength() {
    return const WorkoutSummary(
      number: 70,
      startTime: 1723000000,
      endTime: 1723001200,
      durationSec: 1200,
      type: 140,
      calories: 200,
      hrMin: 84,
      hrMax: 135,
      load: 12,
    );
  }

  Future<void> pumpReady(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('AE1: locked peel + laps shows HR curve and interval charts',
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
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                InSessionHrCurveHost(
                  workout: swim(),
                  preloadedStreamPoints: locked,
                ),
                const SwimSessionCharts(laps: laps),
              ],
            ),
          ),
        ),
      ),
    );
    await pumpReady(tester);

    expect(find.text('bpm · in-session samples'), findsWidgets);
    expect(find.text('Pace by interval'), findsOneWidget);
    expect(find.text('Cadence'), findsNothing);
  });

  testWidgets('AE1: locked peel without laps still shows the HR curve',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                InSessionHrCurveHost(
                  workout: swim(type: 8),
                  preloadedStreamPoints: locked,
                ),
                const SwimSessionCharts(laps: []),
              ],
            ),
          ),
        ),
      ),
    );
    await pumpReady(tester);

    expect(find.text('bpm · in-session samples'), findsWidgets);
    expect(find.text('Session charts'), findsNothing);
  });

  testWidgets('AE3: no peel omits curve with no HR-absent copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: const Scaffold(
          body: InSessionHrCurveHost(
            workout: WorkoutSummary(
              number: 1,
              startTime: 1,
              endTime: 2,
              durationSec: 1,
              type: 6,
            ),
            preloadedStreamPoints: [],
          ),
        ),
      ),
    );
    await pumpReady(tester);

    expect(find.text('bpm · in-session samples'), findsNothing);
    expect(find.textContaining('Heart rate — hidden'), findsNothing);
    expect(find.textContaining('HR absent'), findsNothing);
    expect(find.text('Loading session…'), findsNothing);
  });

  testWidgets('AE4: sampleCount present without lock still omits curve',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: Scaffold(
          body: InSessionHrCurveHost(
            workout: swim(sampleCount: 40),
            preloadedStreamPoints: const [],
          ),
        ),
      ),
    );
    await pumpReady(tester);

    expect(find.text('bpm · in-session samples'), findsNothing);
    expect(find.textContaining('Heart rate — hidden'), findsNothing);
  });

  testWidgets('AE2: strength locked peel shows curve beside min-max tiles',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StrengthSessionAnalytics(
              workout: strength(),
              historyOverride: const [],
              preloadedStreamPoints: locked,
            ),
          ),
        ),
      ),
    );
    await pumpReady(tester);

    expect(find.text('84–135'), findsOneWidget);
    expect(find.text('bpm · in-session samples'), findsWidgets);
    expect(find.text('Cadence'), findsNothing);
    expect(find.text('This session'), findsOneWidget);
  });

  testWidgets('AE3: strength without peel keeps min-max and omits curve',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StrengthSessionAnalytics(
              workout: strength(),
              historyOverride: const [],
              preloadedStreamPoints: const [],
            ),
          ),
        ),
      ),
    );
    await pumpReady(tester);

    expect(find.text('84–135'), findsOneWidget);
    expect(find.text('bpm · in-session samples'), findsNothing);
  });

  testWidgets('AE6: partial locked series still charts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BpTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StrengthSessionAnalytics(
              workout: strength(),
              historyOverride: const [],
              preloadedStreamPoints: const [
                RunStreamPoint(offsetSec: 0, hrBpm: 90),
                RunStreamPoint(offsetSec: 5, hrBpm: 110),
              ],
            ),
          ),
        ),
      ),
    );
    await pumpReady(tester);

    expect(find.text('bpm · in-session samples'), findsWidgets);
  });
}
