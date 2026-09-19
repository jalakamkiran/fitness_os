import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/data/run_session_store.dart';
import 'package:fitness_os/features/workout_history/domain/in_session_hr_lock.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';
import 'package:fitness_os/features/workout_history/presentation/widgets/run_session_charts.dart';

/// Load peeled WorkoutData pages, lock as in-session HR, and chart or shrink.
///
/// Pending IO shows sport-neutral `Loading session…`. Missing peel, failed
/// lock, or IO error → [SizedBox.shrink] (no empty-chart chrome).
class InSessionHrCurveHost extends StatefulWidget {
  const InSessionHrCurveHost({
    super.key,
    required this.workout,
    this.runSessionStore,
    this.preloadedStreamPoints,
  });

  final WorkoutSummary workout;
  final RunSessionStore? runSessionStore;

  /// Test seam: skip side-file IO when non-null.
  final List<RunStreamPoint>? preloadedStreamPoints;

  @override
  State<InSessionHrCurveHost> createState() => _InSessionHrCurveHostState();
}

class _InSessionHrCurveHostState extends State<InSessionHrCurveHost> {
  Future<List<RunStreamPoint>>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedStreamPoints != null) return;
    final store = _resolveStore();
    if (store == null) return;
    _future = _load(store);
  }

  RunSessionStore? _resolveStore() {
    if (widget.runSessionStore != null) return widget.runSessionStore;
    try {
      return sl<RunSessionStore>();
    } catch (_) {
      return null;
    }
  }

  Future<List<RunStreamPoint>> _load(RunSessionStore store) async {
    try {
      final pages = await store.loadDataPages(widget.workout.number);
      return lockInSessionHrPoints(
        pages,
        workoutType: widget.workout.observedType ?? widget.workout.type,
        hrMin: widget.workout.hrMin,
        hrMax: widget.workout.hrMax,
      );
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final preloaded = widget.preloadedStreamPoints;
    if (preloaded != null) {
      return _chartOrShrink(preloaded);
    }
    final future = _future;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<List<RunStreamPoint>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Loading session…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: FathomColors.of(context).inkDim,
                  ),
            ),
          );
        }
        return _chartOrShrink(snap.data ?? const []);
      },
    );
  }

  Widget _chartOrShrink(List<RunStreamPoint> points) {
    final hrOnly = [
      for (final p in points)
        if (p.hrBpm != null)
          RunStreamPoint(offsetSec: p.offsetSec, hrBpm: p.hrBpm),
    ];
    if (hrOnly.length < 2) return const SizedBox.shrink();
    return RunSessionCharts(
      points: hrOnly,
      title: 'Heart rate',
      caption: 'bpm · in-session samples',
      hrCaption: 'bpm · in-session samples',
      showStoryTabs: false,
    );
  }
}
