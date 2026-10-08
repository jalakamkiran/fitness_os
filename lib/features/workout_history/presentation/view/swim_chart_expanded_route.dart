import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/swim_session_charts.dart';

class SwimChartExpandedArgs {
  const SwimChartExpandedArgs({
    required this.laps,
    required this.series,
    this.hrPoints = const [],
  });

  final List<SwimLapMetrics> laps;
  final SwimChartSeries series;
  final List<RunStreamPoint> hrPoints;
}

class SwimChartExpandedRoute {
  static const String path = '/swim_chart_expanded';

  static void register() {
    AppRouter.register(
      path,
      (context) {
        final args =
            ModalRoute.of(context)?.settings.arguments as SwimChartExpandedArgs?;
        if (args == null) {
          return const Scaffold(
            body: Center(child: Text('Missing chart data')),
          );
        }
        return SwimChartExpandedScreen(args: args);
      },
    );
  }

  static Future<SwimChartSeries?> open(
    BuildContext context, {
    required List<SwimLapMetrics> laps,
    required SwimChartSeries series,
    List<RunStreamPoint> hrPoints = const [],
  }) async {
    // Named routes from AppRouter are untyped MaterialPageRoute<dynamic>.
    final result = await Navigator.pushNamed(
      context,
      path,
      arguments: SwimChartExpandedArgs(
        laps: laps,
        series: series,
        hrPoints: hrPoints,
      ),
    );
    return result is SwimChartSeries ? result : null;
  }
}

/// Full-bleed landscape-oriented chart analysis.
class SwimChartExpandedScreen extends StatefulWidget {
  const SwimChartExpandedScreen({super.key, required this.args});

  final SwimChartExpandedArgs args;

  @override
  State<SwimChartExpandedScreen> createState() =>
      _SwimChartExpandedScreenState();
}

class _SwimChartExpandedScreenState extends State<SwimChartExpandedScreen> {
  late SwimChartSeries _series;
  List<DeviceOrientation>? _previous;

  @override
  void initState() {
    super.initState();
    _series = widget.args.series;
    _lockLandscape();
  }

  Future<void> _lockLandscape() async {
    _previous = List<DeviceOrientation>.from(
      const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _restoreOrientations() async {
    final restore = _previous ??
        const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
    await SystemChrome.setPreferredOrientations(restore);
  }

  void _dismiss() {
    // Restore orientations without awaiting — SystemChrome can hang under tests.
    _restoreOrientations();
    Navigator.of(context).pop(_series);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _series == SwimChartSeries.hr
              ? 'HR · expanded'
              : 'Chart analysis',
        ),
        leading: IconButton(
          key: const Key('swim-chart-expanded-close'),
          icon: const Icon(Icons.close),
          onPressed: _dismiss,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SwimSessionCharts(
            key: const Key('swim-chart-expanded-body'),
            laps: widget.args.laps,
            hrPoints: widget.args.hrPoints,
            initialSeries: _series,
            showExpand: false,
            onSeriesChanged: (s) => setState(() => _series = s),
          ),
        ),
      ),
    );
  }
}
