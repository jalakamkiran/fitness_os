import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_detail_screen.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_pace_splits_table.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_session_charts.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_session_sections.dart';

WorkoutSummary _run({
  required int number,
  int type = 2,
  int? steps,
  int? distanceM,
  int? hrMin,
  int? hrMax,
  int? hrPeak,
  int? calories,
  int durationSec = 1800,
}) {
  const start = 1700000000;
  return WorkoutSummary(
    number: number,
    startTime: start,
    endTime: start + durationSec,
    durationSec: durationSec,
    type: type,
    steps: steps,
    distanceM: distanceM,
    hrMin: hrMin,
    hrMax: hrMax,
    hrPeak: hrPeak,
    calories: calories,
  );
}

/// Advance a couple of frames — avoid [pumpAndSettle] (charts may never idle).
Future<void> _pumpReady(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late RunSessionStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fos_run_detail_');
    store = RunSessionStore(rootOverride: () => tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('RunSessionMetrics invent-guard (AE3 / AE4)', () {
    test('fromSummary only maps steps — never invents VO/balance/zones', () {
      final m = RunSessionMetrics.fromSummary(
        _run(number: 1, steps: 4200, distanceM: 5000),
      );
      expect(m.steps, 4200);
      expect(m.hasFormTiles, isTrue);
      expect(RunInventGuard.showsVo2(m), isFalse);
      expect(RunInventGuard.showsVerticalOscillation(m), isFalse);
      expect(RunInventGuard.showsBalance(m), isFalse);
      expect(RunInventGuard.showsNativeZoneMinutes(m), isFalse);
      expect(RunInventGuard.showsThisRunTraining(m), isFalse);
      expect(m.hasNativeZones, isFalse);
      expect(m.hasThisRunTraining, isFalse);
    });

    test('decodeRunSamplePoints never invents series from opaque pages', () {
      const pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x7a, len: 4, bodyBase64: 'AQIDBA=='),
          ],
        ),
      ];
      expect(decodeRunSamplePoints(pages), isEmpty);
      expect(decodeRunSamplePoints(const []), isEmpty);
    });

    test('pace splits require distance or pace scalars', () {
      expect(
        runPaceSplitsFromPages(const [
          PeeledPageBodies(
            index: 0,
            bodies: [
              LeftoverTlvBody(id: 1, len: 1, bodyBase64: 'AQ=='),
            ],
          ),
        ]),
        isEmpty,
      );
      final splits = runPaceSplitsFromPages(const [
        PeeledPageBodies(index: 1, bodies: [], distanceM: 1000, paceSec: 330),
        PeeledPageBodies(index: 0, bodies: [], distanceM: 1000, paceSec: 310),
      ]);
      expect(splits, hasLength(2));
      expect(splits.first.index, 0);
      expect(splits.first.paceSec, 310);
    });
  });

  group('WorkoutDetailScreen Run IA (AE1 / AE8)', () {
    testWidgets('Outdoor Run: header + form steps; invent-guard omits VO/zones',
        (tester) async {
      final workout = _run(
        number: 10,
        type: 2,
        steps: 5123,
        distanceM: 5000,
        hrMin: 120,
        hrMax: 168,
        calories: 420,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: workout,
            // Skip side-file IO in widget tests (fake-async zone).
            preloadedPaceSplits: const [],
            preloadedStreamPoints: const [],
          ),
        ),
      );
      await _pumpReady(tester);

      expect(find.text('Session'), findsOneWidget);
      expect(find.text('Form'), findsOneWidget);
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('5123'), findsOneWidget);
      expect(find.text('Heart rate'), findsOneWidget);
      expect(find.textContaining('5000 m'), findsOneWidget);

      // Invent-guard: named undecoded tiles absent (AE3 / AE4).
      expect(find.text('VO₂ max'), findsNothing);
      expect(find.text('Vertical oscillation'), findsNothing);
      expect(find.text('Balance'), findsNothing);
      expect(find.text('Heart rate zones'), findsNothing);
      expect(find.text('This run'), findsNothing);
      expect(find.text('Zone 1'), findsNothing);

      // No charts without decoded streams (AE2).
      expect(find.text('Session charts'), findsNothing);
      expect(find.text('Splits'), findsNothing);

      // Silent omit — no “tiles absent” / enrichment empty copy on Run path.
      expect(find.textContaining('No enrichment counts'), findsNothing);
      // No U5 export affordance yet.
      expect(find.textContaining('Export'), findsNothing);
    });

    testWidgets('Indoor Run (AE8): thinner show-fetched — steps only form',
        (tester) async {
      final workout = _run(number: 11, type: 5, steps: 800);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: workout,
            preloadedPaceSplits: const [],
            preloadedStreamPoints: const [],
          ),
        ),
      );
      await _pumpReady(tester);

      expect(find.textContaining('Indoor run'), findsWidgets);
      expect(find.text('Form'), findsOneWidget);
      expect(find.text('800'), findsOneWidget);
      expect(find.text('VO₂ max'), findsNothing);
      expect(find.text('Session charts'), findsNothing);
      expect(find.text('Splits'), findsNothing);
    });

    testWidgets('legacy header only when no steps / HR / streams (empty-of-new)',
        (tester) async {
      final workout = _run(number: 12, type: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: workout,
            preloadedPaceSplits: const [],
            preloadedStreamPoints: const [],
          ),
        ),
      );
      await _pumpReady(tester);

      expect(find.text('Session'), findsOneWidget);
      expect(find.text('Form'), findsNothing);
      expect(find.text('This run'), findsNothing);
      expect(find.text('Heart rate zones'), findsNothing);
      expect(find.text('Splits'), findsNothing);
      expect(find.text('Session charts'), findsNothing);
    });

    testWidgets('IA order smoke: Form before Splits before Charts',
        (tester) async {
      final workout = _run(number: 20, steps: 1000, distanceM: 1000);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: workout,
            preloadedPaceSplits: const [
              RunPaceSplit(index: 0, distanceM: 1000, paceSec: 300),
            ],
            // Opaque/undecoded → still no chart points (AE2).
            preloadedStreamPoints: const [],
          ),
        ),
      );
      await _pumpReady(tester);

      final formY = tester.getTopLeft(find.text('Form')).dy;
      final splitsY = tester.getTopLeft(find.text('Splits')).dy;
      expect(formY, lessThan(splitsY));
      expect(find.text('Session charts'), findsNothing);
    });
  });

  group('RunPaceSplitsTable / RunSessionCharts widgets', () {
    testWidgets('splits table shows when distance/pace present', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RunPaceSplitsTable(
              splits: [
                RunPaceSplit(index: 0, distanceM: 1000, paceSec: 310),
                RunPaceSplit(index: 1, distanceM: 1000, paceSec: 320),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Splits'), findsOneWidget);
      expect(find.text('1,000 m'), findsNWidgets(2));
      expect(find.text('5:10 /km'), findsOneWidget);
    });

    testWidgets('splits table hides when no distance/pace', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RunPaceSplitsTable(
              splits: [RunPaceSplit(index: 0)],
            ),
          ),
        ),
      );
      expect(find.text('Splits'), findsNothing);
    });

    testWidgets('charts hide on empty points (AE2)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RunSessionCharts(points: [])),
        ),
      );
      expect(find.text('Session charts'), findsNothing);
    });

    testWidgets('charts show Pace then HR when points exist', (tester) async {
      const points = [
        RunStreamPoint(offsetSec: 0, paceSecPerKm: 330, hrBpm: 140),
        RunStreamPoint(offsetSec: 60, paceSecPerKm: 340, hrBpm: 145),
        RunStreamPoint(offsetSec: 120, paceSecPerKm: 335, hrBpm: 150),
      ];
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RunSessionCharts(points: points),
            ),
          ),
        ),
      );
      expect(find.text('Session charts'), findsOneWidget);
      expect(find.text('Pace'), findsOneWidget);
      expect(find.text('Heart rate'), findsOneWidget);
      final paceY = tester.getTopLeft(find.text('Pace')).dy;
      final hrY = tester.getTopLeft(find.text('Heart rate')).dy;
      expect(paceY, lessThan(hrY));
    });
  });

  group('RunSessionStreamsSection', () {
    testWidgets('omits splits/charts when side-files empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RunSessionStreamsSection(
              workoutNumber: 99,
              preloadedSplits: [],
              preloadedPoints: [],
            ),
          ),
        ),
      );
      await _pumpReady(tester);
      expect(find.text('Splits'), findsNothing);
      expect(find.text('Session charts'), findsNothing);
    });

    testWidgets('shows splits from pace meta without inventing charts',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RunSessionStreamsSection(
              workoutNumber: 30,
              preloadedSplits: [
                RunPaceSplit(index: 0, distanceM: 1000, paceSec: 300),
              ],
              // Opaque data pages must not invent HR/pace charts (AE2 / AE3).
              preloadedPoints: [],
            ),
          ),
        ),
      );
      await _pumpReady(tester);

      expect(find.text('Splits'), findsOneWidget);
      expect(find.text('Session charts'), findsNothing);
    });
  });

  group('peel retains pace distance/pace for splits', () {
    test('scalar-only pace blocks survive peel + store round-trip', () async {
      final peeled = WorkoutChannelPeel.peel({
        'number': 40,
        'startTime': 10,
        'endTime': 20,
        'durationSec': 10,
        'type': 2,
        'paceCount': 2,
        'paceBlocks': [
          {'index': 0, 'distanceM': 1000, 'paceSec': 300},
          {'index': 1, 'distanceM': 1000, 'paceSec': 310},
        ],
      });
      expect(peeled.paceBlocks, hasLength(2));
      expect(peeled.paceBlocks.first.distanceM, 1000);
      expect(peeled.paceBlocks.first.paceSec, 300);
      expect(peeled.hasBodiesToPersist, isTrue);

      await store.save(peeled);
      final loaded = await store.loadPaceBlocks(40);
      expect(loaded, hasLength(2));
      expect(loaded.first.distanceM, 1000);
      expect(loaded.first.paceSec, 300);
      expect(runPaceSplitsFromPages(loaded), hasLength(2));
    });
  });
}
