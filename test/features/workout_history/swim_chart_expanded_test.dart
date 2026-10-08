import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/view/swim_chart_expanded_route.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';

List<SwimLapMetrics> _denseLaps(int n) => [
      for (var i = 0; i < n; i++)
        SwimLapMetrics(
          index: i,
          distanceM: 25,
          durationSec: 40 + (i % 5),
          strokes: 18,
          swolf: 58 + (i % 3),
          paceSecPer100m: 155 + (i % 10),
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppRouter.clearForTest();
    SwimChartExpandedRoute.register();
  });

  testWidgets('AE3: dense session exposes expand → landscape analysis',
      (tester) async {
    final laps = _denseLaps(40);

    await tester.pumpWidget(
      MaterialApp(
        routes: AppRouter.routes,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SwimSessionCharts(
              laps: laps,
              onExpand: (series) => SwimChartExpandedRoute.open(
                tester.element(find.byType(SwimSessionCharts)),
                laps: laps,
                series: series,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('swim-chart-expand')), findsOneWidget);
    expect(find.text('Expand'), findsOneWidget);

    await tester.tap(find.byKey(const Key('swim-chart-expand')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('swim-chart-expanded-body')), findsOneWidget);
    expect(find.text('Chart analysis'), findsOneWidget);
    expect(find.byKey(const Key('swim-series-pace')), findsWidgets);

    await tester.tap(find.byKey(const Key('swim-chart-expanded-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('swim-chart-expanded-body')), findsNothing);
  });

  testWidgets('shorter sessions still expand on demand', (tester) async {
    final laps = _denseLaps(4);

    await tester.pumpWidget(
      MaterialApp(
        routes: AppRouter.routes,
        home: Scaffold(
          body: SwimSessionCharts(
            laps: laps,
            onExpand: (series) => SwimChartExpandedRoute.open(
              tester.element(find.byType(SwimSessionCharts)),
              laps: laps,
              series: series,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('swim-chart-expand')), findsOneWidget);
  });
}
