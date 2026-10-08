import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_interval_sets.dart';

List<SwimLapMetrics> _laps(int n) => [
      for (var i = 0; i < n; i++)
        SwimLapMetrics(
          index: i,
          distanceM: 25,
          durationSec: 40 + (i % 5),
          strokes: 18,
          swolf: 58,
          paceSecPer100m: 160 + (i % 8),
        ),
    ];

void main() {
  test('groups ≤24 into warmup / main / cool', () {
    final sets = buildSwimIntervalSets(_laps(16));
    expect(sets.map((s) => s.id), ['warmup', 'main', 'cool']);
    expect(sets.every((s) => s.laps.isNotEmpty), isTrue);
  });

  test('dense sessions use blocks', () {
    final sets = buildSwimIntervalSets(_laps(40));
    expect(sets.length, 4);
    expect(sets.first.id, 'block1');
  });

  testWidgets('renders collapsible sets with length bars', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SwimIntervalSetsView(
              laps: _laps(12),
              poolLengthM: 25,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('swim-interval-sets')), findsOneWidget);
    expect(find.textContaining('Main set'), findsOneWidget);
    expect(find.textContaining('Warmup'), findsOneWidget);
    // Main open by default → length times visible.
    expect(find.textContaining('0:'), findsWidgets);

    await tester.tap(find.byKey(const Key('swim-set-warmup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('swim-set-warmup')), findsOneWidget);
  });
}
