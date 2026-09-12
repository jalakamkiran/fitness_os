import 'dart:convert';
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

  
  group('annotateRunSplits / TE cues', () {
    test('tags walk cool-down and fastest run km', () {
      final rows = annotateRunSplits(const [
        RunPaceSplit(index: 0, distanceM: 1000, paceSec: 382),
        RunPaceSplit(index: 1, distanceM: 1000, paceSec: 369),
        RunPaceSplit(index: 2, distanceM: 790, paceSec: 694),
      ]);
      expect(rows.length, 3);
      expect(rows[0].isWalk, isFalse);
      expect(rows[1].isFastest, isTrue);
      expect(rows[2].isWalk, isTrue);
      expect(detectRunWalkTransition(rows.map((r) => r.split).toList()), isTrue);
    });

    test('teBandHint maps maintain band', () {
      expect(teBandHint(2.3), 'Maintain band');
    });
  });

group('RunSessionMetrics invent-guard (AE3 / AE4)', () {
    test('fromSummary maps steps + stride — never invents VO/balance/zones', () {
      final m = RunSessionMetrics.fromSummary(
        _run(number: 1, steps: 4200, distanceM: 5000),
      );
      expect(m.steps, 4200);
      expect(m.strideCm, 119); // 5000/4200*100
      expect(m.hasFormTiles, isTrue);
      expect(RunInventGuard.showsVo2(m), isFalse);
      expect(RunInventGuard.showsVerticalOscillation(m), isFalse);
      expect(RunInventGuard.showsBalance(m), isFalse);
      expect(RunInventGuard.showsNativeZoneMinutes(m), isFalse);
      expect(RunInventGuard.showsThisRunTraining(m), isFalse);
      expect(m.hasNativeZones, isFalse);
      expect(m.hasThisRunTraining, isFalse);
    });

    test('fromLeftovers locks #60 watch scalars', () {
      final bodies = <LeftoverTlvBody>[
        LeftoverTlvBody(id: 0x0b, len: 4, bodyBase64: base64Encode([0, 0, 0, 27])),
        LeftoverTlvBody(id: 0x0d, len: 4, bodyBase64: base64Encode([0, 0, 0, 66])),
        LeftoverTlvBody(id: 0x0e, len: 4, bodyBase64: base64Encode([0, 0, 0, 23])),
        LeftoverTlvBody(id: 0x11, len: 2, bodyBase64: base64Encode([0x04, 0xec])),
        LeftoverTlvBody(id: 0x1b, len: 4, bodyBase64: base64Encode([0, 0, 0, 54])),
        LeftoverTlvBody(
          id: 0x1c,
          len: 4,
          bodyBase64: base64Encode([0, 0, 0x23, 0x9c]),
        ),
        LeftoverTlvBody(
          id: 0x1d,
          len: 4,
          bodyBase64: base64Encode([0, 0, 0x23, 0x82]),
        ),
        LeftoverTlvBody(id: 0x20, len: 1, bodyBase64: base64Encode([17])),
        LeftoverTlvBody(
          id: 0xe7,
          len: 11,
          bodyBase64: base64Encode(
            [0x68, 0x04, 0x11, 0xe1, 0xca, 0x43, 0x69, 0x03, 0x32, 0x39, 0x30],
          ),
        ),
        LeftoverTlvBody(
          id: 0xe7,
          len: 17,
          bodyBase64: base64Encode([
            0x68, 0x04, 0x11, 0xe1, 0xca, 0x4a, 0x69, 0x09,
            ...utf8.encode('50.070011'),
          ]),
        ),
        LeftoverTlvBody(
          id: 0xe7,
          len: 17,
          bodyBase64: base64Encode([
            0x68, 0x04, 0x11, 0xe1, 0xca, 0x4b, 0x69, 0x09,
            ...utf8.encode('10.200000'),
          ]),
        ),
        LeftoverTlvBody(
          id: 0xe7,
          len: 14,
          bodyBase64: base64Encode([
            0x68, 0x04, 0x11, 0xe1, 0xca, 0xaf, 0x69, 0x06,
            ...utf8.encode('158000'),
          ]),
        ),
      ];
      final m = RunSessionMetrics.fromLeftovers(
        bodies,
        steps: 2905,
        distanceM: 2790,
      );
      expect(m.sessionLoad, 66);
      expect(m.aerobicEffect, closeTo(2.3, 0.01));
      expect(m.anaerobicEffect, closeTo(1.7, 0.01));
      expect(m.recoverySec, 1260 * 60); // 21 h
      expect(m.elevGainM, closeTo(2.7, 0.01));
      expect(m.elevLossM, closeTo(5.4, 0.01));
      expect(m.maxAltitudeM, closeTo(911.6, 0.01));
      expect(m.minAltitudeM, closeTo(909.0, 0.01));
      expect(m.gctMs, 290);
      expect(m.verticalOscillationCm, closeTo(10.2, 0.01));
      expect(m.balancePct, closeTo(50.07, 0.01));
      expect(m.activeCalories, 158);
      expect(m.strideCm, 96);
      expect(RunInventGuard.showsThisRunTraining(m), isTrue);
      expect(RunInventGuard.showsVerticalOscillation(m), isTrue);
      expect(RunInventGuard.showsBalance(m), isTrue);
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

    test('decodeRunSamplePoints reads GT5 0x05 HR records', () {
      // 00 00 23 cad hr 00 .. ..
      final rec1 = [0x00, 0x00, 0x23, 100, 140, 0x00, 0x0D, 0x08];
      final rec2 = [0x00, 0x00, 0x23, 110, 150, 0x00, 0x17, 0x0C];
      final body = base64Encode([...rec1, ...rec2]);
      final points = decodeRunSamplePoints([
        PeeledPageBodies(
          index: 0,
          bodies: [LeftoverTlvBody(id: 0x05, len: 16, bodyBase64: body)],
        ),
      ]);
      expect(points, hasLength(2));
      expect(points[0].offsetSec, 0);
      expect(points[0].hrBpm, 140);
      expect(points[0].cadenceSpm, 100);
      expect(points[0].paceSecPerKm, isNull); // pace from splits, not samples
      expect(points[1].offsetSec, 5);
      expect(points[1].hrBpm, 150);
    });

    test('0x83 flag0 decodes watch km splits; flag1 skipped', () {
      // #60 lock: 382s / 369s / 790m @ 694 s/km; flag1 rows ignored.
      final km1 = [
        0x04, 0x02, 0x00, 0x01,
        0x05, 0x01, 0x00,
        0x06, 0x04, 0x00, 0x00, 0x01, 0x7e, // 382
      ];
      final other = [
        0x04, 0x02, 0x00, 0x01,
        0x05, 0x01, 0x01, // flag 1
        0x06, 0x04, 0x00, 0x00, 0x02, 0x60, // 608
      ];
      final km2 = [
        0x04, 0x02, 0x00, 0x02,
        0x05, 0x01, 0x00,
        0x06, 0x04, 0x00, 0x00, 0x01, 0x71, // 369
      ];
      final partial = [
        0x04, 0x02, 0x00, 0x02,
        0x05, 0x01, 0x00,
        0x06, 0x04, 0x00, 0x00, 0x02, 0xb6, // 694
        0x07, 0x02, 0x01, 0xff,
        0x09, 0x02, 0x1e, 0xdc, // 7900 → 790 m
      ];
      final splits = runPaceSplitsFromPages([
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x83, len: km1.length, bodyBase64: base64Encode(km1)),
            LeftoverTlvBody(id: 0x83, len: other.length, bodyBase64: base64Encode(other)),
            LeftoverTlvBody(id: 0x83, len: km2.length, bodyBase64: base64Encode(km2)),
            LeftoverTlvBody(
              id: 0x83,
              len: partial.length,
              bodyBase64: base64Encode(partial),
            ),
          ],
        ),
      ]);
      expect(splits, hasLength(3));
      expect(splits[0].distanceM, 1000);
      expect(splits[0].paceSec, 382);
      expect(splits[1].distanceM, 1000);
      expect(splits[1].paceSec, 369);
      expect(splits[2].distanceM, 790);
      expect(splits[2].paceSec, 694);
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

    test('merge applies split pace steps onto HR samples', () {
      final splits = [
        const RunPaceSplit(index: 0, distanceM: 1000, paceSec: 382),
        const RunPaceSplit(index: 1, distanceM: 790, paceSec: 694),
      ];
      final paceSteps = runPaceSeriesFromSplits(splits);
      final merged = mergeRunStreamPaceAndHr(
        hrSamples: const [
          RunStreamPoint(offsetSec: 0, hrBpm: 140),
          RunStreamPoint(offsetSec: 200, hrBpm: 170),
          RunStreamPoint(offsetSec: 900, hrBpm: 130),
        ],
        paceSteps: paceSteps,
      );
      expect(merged[0].paceSecPerKm, 382);
      expect(merged[1].paceSecPerKm, 382);
      expect(merged[2].paceSecPerKm, 694);
      expect(merged[2].hrBpm, 130);
    });
  });

  group('WorkoutDetailScreen Run IA (AE1 / AE8)', () {
    testWidgets('product UI: basics + HR stimulus, invent-guard on missing form',
        (tester) async {
      final workout = _run(
        number: 10,
        type: 2,
        steps: 5123,
        distanceM: 5000,
        hrMin: 120,
        hrMax: 168,
        calories: 420,
        durationSec: 1800,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: workout,
            preloadedPaceSplits: const [],
            preloadedStreamPoints: const [],
            preloadedLeftovers: const [],
          ),
        ),
      );
      await _pumpReady(tester);

      expect(find.text('OUTDOOR'), findsOneWidget);
      expect(find.text('5.00 km'), findsOneWidget);
      expect(find.text('THIS SESSION'), findsOneWidget);
      expect(find.text('120–168'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('TERRAIN'), 300);
      expect(find.text('5123'), findsOneWidget);

      expect(find.text('VO₂ max'), findsNothing);
      expect(find.text('Vertical oscillation'), findsNothing);
      expect(find.textContaining('BALANCE'), findsNothing);
      expect(find.text('Heart rate zones'), findsNothing);
      expect(find.text('This run'), findsNothing);
      expect(find.text('Zone 1'), findsNothing);
      expect(find.text('Totals leftovers (fetch probe)'), findsNothing);

      expect(find.text('Session story'), findsNothing);
      expect(find.text('Session charts'), findsNothing);
      expect(find.text('SPLITS'), findsNothing);

      expect(find.textContaining('No enrichment counts'), findsNothing);
      expect(find.text('Export for AI'), findsNothing);
    });

    testWidgets('Indoor Run (AE8): thinner show-fetched — steps in terrain',
        (tester) async {
      final workout = _run(number: 11, type: 5, steps: 800);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: workout,
            preloadedPaceSplits: const [],
            preloadedStreamPoints: const [],
            preloadedLeftovers: const [],
          ),
        ),
      );
      await _pumpReady(tester);

      expect(find.textContaining('Indoor run'), findsWidgets);
      expect(find.text('INDOOR'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('800'), 300);
      expect(find.text('800'), findsOneWidget);
      expect(find.text('VO₂ max'), findsNothing);
      expect(find.text('Session story'), findsNothing);
      expect(find.text('SPLITS'), findsNothing);
    });

    testWidgets('empty-of-new: mode chip only — no invented tiles',
        (tester) async {
      final workout = _run(number: 12, type: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: workout,
            preloadedPaceSplits: const [],
            preloadedStreamPoints: const [],
            preloadedLeftovers: const [],
          ),
        ),
      );
      await _pumpReady(tester);

      expect(find.text('OUTDOOR'), findsOneWidget);
      expect(find.textContaining('AFTER THIS SESSION'), findsOneWidget);
      expect(find.text('Form'), findsNothing);
      expect(find.text('This run'), findsNothing);
      expect(find.text('Heart rate zones'), findsNothing);
      expect(find.text('SPLITS'), findsNothing);
      expect(find.text('Session story'), findsNothing);
    });

    testWidgets('IA order smoke: basics before Splits before Charts',
        (tester) async {
      final workout = _run(
        number: 20,
        steps: 1000,
        distanceM: 1000,
        durationSec: 300,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: workout,
            preloadedPaceSplits: const [
              RunPaceSplit(index: 0, distanceM: 1000, paceSec: 300),
            ],
            preloadedStreamPoints: const [],
            preloadedLeftovers: const [],
          ),
        ),
      );
      await _pumpReady(tester);

      expect(find.text('1.00 km'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('SPLITS'), 300);
      expect(find.text('SPLITS'), findsOneWidget);
      expect(find.text('Session story'), findsNothing);
      expect(find.text('FASTEST'), findsOneWidget);
    });

    testWidgets('product UI: leftovers fill TE + form gauges', (tester) async {
      final bodies = <LeftoverTlvBody>[
        LeftoverTlvBody(id: 0x0d, len: 4, bodyBase64: base64Encode([0, 0, 0, 66])),
        LeftoverTlvBody(id: 0x0e, len: 4, bodyBase64: base64Encode([0, 0, 0, 23])),
        LeftoverTlvBody(id: 0x11, len: 2, bodyBase64: base64Encode([0x04, 0xec])),
        LeftoverTlvBody(id: 0x20, len: 1, bodyBase64: base64Encode([17])),
        LeftoverTlvBody(
          id: 0xe7,
          len: 11,
          bodyBase64: base64Encode(
            [0x68, 0x04, 0x11, 0xe1, 0xca, 0x43, 0x69, 0x03, 0x32, 0x39, 0x30],
          ),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailScreen(
            workout: _run(
              number: 60,
              type: 1,
              steps: 2905,
              distanceM: 2790,
              durationSec: 1300,
              calories: 248,
              hrMin: 84,
              hrMax: 181,
            ),
            preloadedPaceSplits: const [
              RunPaceSplit(index: 0, distanceM: 1000, paceSec: 382),
              RunPaceSplit(index: 1, distanceM: 1000, paceSec: 369),
              RunPaceSplit(index: 2, distanceM: 790, paceSec: 694),
            ],
            preloadedStreamPoints: const [],
            preloadedLeftovers: bodies,
          ),
        ),
      );
      await _pumpReady(tester);

      expect(find.text('RUN → WALK'), findsOneWidget);
      expect(find.text('2.3'), findsOneWidget);
      expect(find.text('66'), findsOneWidget);
      expect(find.text('21h'), findsOneWidget);
      expect(find.text('SPLITS'), findsOneWidget);
      expect(find.text('FASTEST'), findsOneWidget);
      expect(find.text('GCT'), findsOneWidget);
      expect(find.text('Totals leftovers (fetch probe)'), findsNothing);
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
      expect(find.text("5'10\""), findsOneWidget);
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
      expect(find.text('SPLITS'), findsNothing);
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
      expect(find.text('SPLITS'), findsNothing);
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
