import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_insight.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_screen.dart';

WorkoutSummary _poolSwim({
  int number = 42,
  int distanceM = 1000,
  int durationSec = 1200,
  List<WorkoutSegment>? segments,
}) {
  const start = 1723000000;
  return WorkoutSummary(
    number: number,
    startTime: start,
    endTime: start + durationSec,
    durationSec: durationSec,
    type: 6,
    distanceM: distanceM,
    poolLength: 25,
    laps: segments?.length ?? 16,
    segments: segments,
    dataCount: 12,
    paceCount: 8,
    segmentsCount: segments?.length ?? 16,
    enrichmentStatus: 'ok',
  );
}

List<SwimLapMetrics> _laps(int n, {bool includeNullPace = false}) {
  return [
    for (var i = 0; i < n; i++)
      SwimLapMetrics(
        index: i,
        distanceM: 25,
        durationSec: 40 + (i % 3),
        strokes: 18 + (i % 2),
        swolf: 58 + (i % 4),
        paceSecPer100m: includeNullPace && i == 1 ? null : 160 + i,
      ),
  ];
}

SwimSessionInsight _insight({
  String story = 'Efficient early, then pace and SWOLF slipped later in the set.',
  String? tipTitle = 'Shorten the main set',
  bool withSecondaries = true,
}) {
  return SwimSessionInsight(
    story: story,
    storyDiagnosisId: tipTitle == null ? null : 'fatigue_onset',
    chips: const [
      SwimComparisonChip(
        label: 'Pace',
        deltaLabel: '+4s/100',
        direction: SwimChipDirection.down,
      ),
    ],
    primaryTip: tipTitle == null
        ? null
        : SwimPrimaryTip(
            recId: 'cut_main_set',
            title: tipTitle,
            why: 'Late intervals drifted — keep volume honest next time.',
            sourceDiagnosisId: 'fatigue_onset',
          ),
    kpis: const SwimSessionKpis(
      distanceM: 1000,
      durationPrimaryLabel: '18:00',
      durationHint: 'swim · 2:00 rest',
      avgPaceSecPer100m: 168,
      avgSwolf: 60,
    ),
    secondaryFindings: withSecondaries
        ? const [
            SwimSecondaryFinding(
              diagnosisId: 'pacing_uneven',
              title: 'Uneven pacing',
              body: 'Interval times swung across the set.',
            ),
          ]
        : const [],
  );
}

Future<void> _pumpSwim(
  WidgetTester tester, {
  required WorkoutSummary workout,
  required SwimSessionInsight insight,
  List<SwimLapMetrics>? laps,
  bool digDeeper = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutDetailScreen(
        workout: workout,
        digDeeperOverride: digDeeper,
        swimInsightOverride: insight,
        swimLapsOverride: laps ?? _laps(12),
        historyOverride: const [],
        swimExportBusyOverride: () => false,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AE1 / AE4 athlete fold', () {
    testWidgets('story, tip, KPIs; banned dig-deeper chrome absent',
        (tester) async {
      await _pumpSwim(
        tester,
        workout: _poolSwim(),
        insight: _insight(),
      );

      expect(find.byKey(const Key('swim-coach-story')), findsOneWidget);
      expect(find.byKey(const Key('swim-primary-tip')), findsOneWidget);
      expect(find.byKey(const Key('swim-kpi-strip')), findsOneWidget);
      expect(find.text('Shorten the main set'), findsOneWidget);

      expect(find.text('Enrichment counts'), findsNothing);
      expect(find.textContaining('Sync:'), findsNothing);
      expect(find.textContaining('Type'), findsNothing);
      expect(find.text('P0 metrics'), findsNothing);
      expect(find.text('Samples'), findsNothing);
      expect(find.text('Dev'), findsNothing);
      expect(find.text('Run reasoner'), findsNothing);
      expect(find.text('Qwen3 settings'), findsNothing);
      expect(find.byTooltip('Reasoner settings'), findsNothing);
      expect(find.text('Include filtered laps'), findsNothing);
    });

    testWidgets('multiple findings → one tip; More findings collapsed',
        (tester) async {
      await _pumpSwim(
        tester,
        workout: _poolSwim(),
        insight: _insight(),
      );

      expect(find.byKey(const Key('swim-primary-tip')), findsOneWidget);
      expect(find.text('Shorten the main set'), findsOneWidget);
      expect(find.text('More findings'), findsOneWidget);
      expect(find.text('Uneven pacing'), findsNothing);

      // Findings jump auto-expands More findings (AE6).
      await tester.tap(find.byKey(const Key('swim-jump-findings')));
      await tester.pumpAndSettle();
      expect(find.text('Uneven pacing'), findsOneWidget);
    });

    testWidgets('empty-tip escape keeps KPIs', (tester) async {
      await _pumpSwim(
        tester,
        workout: _poolSwim(),
        insight: _insight(tipTitle: null, withSecondaries: false),
      );

      expect(find.byKey(const Key('swim-empty-tip')), findsOneWidget);
      expect(find.byKey(const Key('swim-kpi-strip')), findsOneWidget);
      expect(find.byKey(const Key('swim-primary-tip')), findsNothing);
    });
  });

  group('AE5 dig-deeper', () {
    testWidgets('flag on shows Dev column and dump chrome', (tester) async {
      await _pumpSwim(
        tester,
        workout: _poolSwim(),
        insight: _insight(),
        digDeeper: true,
      );

      await tester.scrollUntilVisible(
        find.text('Dig deeper'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Dig deeper'), findsOneWidget);
      expect(find.text('Enrichment counts'), findsOneWidget);
      expect(find.text('Dev'), findsOneWidget);
      expect(find.text('Run reasoner'), findsNothing);
      expect(find.byTooltip('Reasoner settings'), findsNothing);
    });
  });

  group('AE6 jump links', () {
    testWidgets('Intervals jump present when laps exist', (tester) async {
      await _pumpSwim(
        tester,
        workout: _poolSwim(),
        insight: _insight(),
        laps: _laps(8),
      );

      expect(find.byKey(const Key('swim-jump-intervals')), findsOneWidget);
      expect(find.byKey(const Key('swim-jump-charts')), findsOneWidget);
      await tester.tap(find.byKey(const Key('swim-jump-intervals')));
      await tester.pumpAndSettle();
      expect(find.text('Intervals'), findsWidgets);
    });
  });

  group('R18 / R23', () {
    testWidgets('open-water uses shared swim shell', (tester) async {
      const start = 1723000000;
      await _pumpSwim(
        tester,
        workout: const WorkoutSummary(
          number: 8,
          startTime: start,
          endTime: start + 900,
          durationSec: 900,
          type: 8,
          distanceM: 800,
        ),
        insight: const SwimSessionInsight(
          story: 'Open-water effort logged — coaching narratives stay light.',
          chips: [],
          kpis: SwimSessionKpis(
            distanceM: 800,
            durationPrimaryLabel: '15:00',
          ),
          secondaryFindings: [],
        ),
        laps: const [],
      );

      expect(find.textContaining('Open water'), findsWidgets);
      expect(find.byTooltip('Reasoner settings'), findsNothing);
    });
  });
}
